<?php
declare(strict_types=1);
require_once __DIR__.'/simulation.php';

const ATLAS_GUARD = "<?php http_response_code(404); exit; __halt_compiler(); ?>\n";
const ATLAS_COLORS = ['69dfbd','73aeef','edc16e','b697ef','f291a1','ed876a','c9dbed','a8cc6a'];

function atlas_country_count(): int {
    static $count = null;
    return $count ??= count(atlas_mod_world()['countries']);
}
function atlas_start_country_count(): int {
    static $count = null;
    return $count ??= count(array_filter(atlas_mod_world()['atlas'],fn($c)=>!$c['enclave_hosts']));
}

function atlas_config(): array {
    $config=require __DIR__.'/config.example.php';
    if (is_file(__DIR__.'/config.php')) $config=array_replace($config,require __DIR__.'/config.php');
    foreach (['max_rooms'=>[1,16],'poll_ms'=>[750,5000],'lease_seconds'=>[10,120]] as $key=>$range)
        if (!is_int($config[$key]) || $config[$key]<$range[0] || $config[$key]>$range[1]) throw new RuntimeException('Invalid config: '.$key);
    $fingerprint=atlas_mod_fingerprint();
    if ($fingerprint!=='') $config['data_dir'].='/mods_'.$fingerprint;
    if (!is_dir($config['data_dir']) && !mkdir($config['data_dir'],0770,true)) throw new RuntimeException('Cannot create data directory');
    return $config;
}
function atlas_transaction(array $config,callable $work): array {
    $started=hrtime(true); $acquired=null; $bytes='';
    $base=$config['data_dir'];
    $lock=fopen($base.'/lock.php','c+');
    if (!$lock || !flock($lock,LOCK_EX)) throw new RuntimeException('Cannot lock storage');
    $acquired=hrtime(true);
    try {
        if (filesize($base.'/lock.php')===0) { fwrite($lock,ATLAS_GUARD); fflush($lock); }
        $path=$base.'/state.php';
        $state=['version'=>1,'users'=>[],'rooms'=>[]];
        if (is_file($path)) {
            $raw=file_get_contents($path);
            if (!str_starts_with($raw,ATLAS_GUARD)) throw new RuntimeException('Invalid storage');
            $state=json_decode(substr($raw,strlen(ATLAS_GUARD)),true,128,JSON_THROW_ON_ERROR);
            if (($state['version']??0)!==1 || !isset($state['users'],$state['rooms'])) throw new RuntimeException('Invalid storage version');
        }
        $result=$work($state);
        $bytes=ATLAS_GUARD.json_encode($state,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
        $temporary=$path.'.tmp.php';
        if (file_put_contents($temporary,$bytes)!==strlen($bytes)) throw new RuntimeException('Cannot write storage');
        if (is_file($path) && !copy($path,$base.'/backup.php')) throw new RuntimeException('Cannot back up storage');
        if (!rename($temporary,$path)) throw new RuntimeException('Cannot replace storage');
        return $result;
    } finally {
        flock($lock,LOCK_UN); fclose($lock);
        if ($config['metrics']??false) error_log('ATLAS metric '.json_encode([
            'lock_ms'=>round(($acquired-$started)/1e6,3),
            'transaction_ms'=>round((hrtime(true)-$started)/1e6,3),
            'state_bytes'=>strlen($bytes), 'rooms'=>count($state['rooms']??[])]));
    }
}
function atlas_name(string $name,int $limit=24): string {
    $name=preg_replace('/[\x00-\x1f\x7f]/u',' ',trim($name));
    $letters=preg_split('//u',$name??'',-1,PREG_SPLIT_NO_EMPTY);
    return $letters?implode('',array_slice($letters,0,$limit)):'Игрок';
}
function atlas_pause(array &$room,string $message): void {
    $room['stage']='lobby'; $room['status']=$message;
    foreach ($room['players'] as &$p) $p['ready']=$p['bot'];
    unset($p);
}
function atlas_offline(array &$room,string $slot): void {
    if (!isset($room['players'][$slot]) || !$room['players'][$slot]['connected']) return;
    $room['players'][$slot]['connected']=false; $room['players'][$slot]['ready']=false;
    unset($room['players'][$slot]['ping_ms'],$room['players'][$slot]['ping_at']);
    if ($room['host']===$slot) foreach ($room['players'] as $id=>$p) if (!$p['bot'] && $p['connected']) { $room['host']=$id; break; }
    atlas_pause($room,'Участник отключился. Ожидаем возвращения и готовности игроков.');
}
function atlas_advance(array &$room,int $now,array $config,AtlasWorld $sim): void {
    if ($room['world'] !== null) $sim->expand_legacy_map($room['world']);
    $end=min($now,$room['time']+120);
    for ($time=$room['time']+1;$time<=$end;$time++) {
        foreach ($room['players'] as $slot=>$p)
            if (!$p['bot'] && $p['connected'] && $time-$p['seen']>$config['lease_seconds']) atlas_offline($room,$slot);
        if ($room['stage']!=='game') break;
        $bots=array_keys(array_filter($room['players'],fn($p)=>$p['bot']));
        $sim->tick($room['world'],$bots);
    }
    foreach ($room['players'] as $slot=>$p)
        if (!$p['bot'] && $p['connected'] && $now-$p['seen']>$config['lease_seconds']) atlas_offline($room,$slot);
    $room['time']=$now;
}
function atlas_country(array $room,string $slot,int $country): bool {
    if ($country<0 || $country>=atlas_country_count()) return false;
    static $atlas = null;
    $atlas ??= atlas_mod_world()['atlas'];
    if ($atlas[$country]['enclave_hosts']) return false;
    $claimed=mr_start_territories($country);
    foreach ($room['players'] as $id=>$p) if ($id!==$slot && array_intersect($claimed,mr_start_territories($p['home']))) return false;
    return $room['world']===null || $room['world']['owners'][$country]==='' || $room['world']['owners'][$country]===$slot;
}
function atlas_player(array $room,string $digest,string $name,bool $bot,int $now): array {
    $home=0;
    while ($home<atlas_country_count() && !atlas_country($room,'',$home)) $home++;
    if ($home===atlas_country_count()) throw new DomainException('Нет свободной стартовой страны.');
    $color=ATLAS_COLORS[0];
    foreach (ATLAS_COLORS as $candidate) if (!in_array($candidate,array_column($room['players'],'color'),true)) { $color=$candidate; break; }
    return ['name'=>$name,'digest'=>$digest,'peer'=>count($room['players'])+2,'bot'=>$bot,'connected'=>true,'ready'=>$bot,'home'=>$home,'color'=>$color,'seen'=>$now];
}
function atlas_ready(array $room): bool {
    if (count($room['players'])<2) return false;
    foreach ($room['players'] as $p) if (!$p['connected'] || !$p['ready']) return false;
    return true;
}
function atlas_lobby_action(array &$room,string $slot,string $action,array $args,int $now,AtlasWorld $sim): void {
    if (!isset($room['players'][$slot]) || !$room['players'][$slot]['connected']) throw new DomainException('Место в комнате недоступно.');
    if ($action==='lobby') { atlas_pause($room,'Общая пауза. Подтвердите готовность для продолжения.'); return; }
    if ($room['stage']==='game') {
        if (!$sim->command($room['world'],$slot,$action,$args)) throw new DomainException('Команда недоступна: проверьте цель, войска и баланс.');
        return;
    }
    $p=&$room['players'][$slot];
    switch ($action) {
        case 'choose':
            if (count($args)!==1 || !is_int($args[0]) || !atlas_country($room,$slot,$args[0]) || isset($room['world']['factions'][$slot])) throw new DomainException('Страна недоступна.');
            $p['home']=$args[0]; $p['ready']=false; break;
        case 'color':
            if (count($args)!==1 || !in_array($args[0],ATLAS_COLORS,true)) throw new DomainException('Неверный цвет.');
            foreach ($room['players'] as $id=>$other) if ($id!==$slot && $other['color']===$args[0]) throw new DomainException('Цвет занят.');
            $p['color']=$args[0]; $p['ready']=false;
            if (isset($room['world']['factions'][$slot])) $room['world']['factions'][$slot]['player_color']=$args[0]; break;
        case 'ready':
            if (count($args)!==1 || !is_bool($args[0])) throw new DomainException('Неверная готовность.');
            $p['ready']=$args[0]; break;
        case 'bot':
            $count=$args[0]??1;
            $free=0;
            for ($country=0;$country<atlas_country_count();$country++) if (atlas_country($room,'',$country)) $free++;
            if ($slot!==$room['host'] || count($args)>1 || !is_int($count) || $count<1 || $count>$free || $count+count($room['players'])>atlas_start_country_count()) throw new DomainException('Недостаточно свободных стран для указанного числа ботов.');
            for ($i=0;$i<$count;$i++) {
                $id='bot_'.bin2hex(random_bytes(6));
                $room['players'][$id]=atlas_player($room,'','Бот '.count($room['players']),true,$now);
            }
            break;
        case 'kick':
            $id=$args[0]??null;
            if ($slot!==$room['host'] || !is_string($id) || $id===$room['host'] || !isset($room['players'][$id])) throw new DomainException('Удаление участника недоступно.');
            if (!$room['players'][$id]['bot']) $room['banned'][]=$room['players'][$id]['digest'];
            $room['banned']=array_slice($room['banned'],-128);
            if ($room['world']!==null) $sim->remove($room['world'],$id);
            unset($room['players'][$id]); break;
        case 'start':
            if ($slot!==$room['host'] || !atlas_ready($room)) throw new DomainException('Не все участники подключены и готовы.');
            if ($room['world']===null) $room['world']=$sim->create();
            foreach ($room['players'] as $id=>$player) if (!isset($room['world']['factions'][$id])) $sim->add($room['world'],$id,$player['home'],$player['color']);
            $room['stage']='game'; $room['time']=$now; break;
        default: throw new DomainException('Неизвестная команда.');
    }
}
function atlas_response(array &$state,string $session,array $config,AtlasWorld $sim): array {
    $user=&$state['users'][$session]; $digest=$user['digest']; $slot='p_'.substr($digest,0,16);
    $directory=[];
    foreach ($state['rooms'] as $id=>$room) $directory[]=['id'=>(string)$id,'name'=>$room['name'],'players'=>count($room['players']),
        'stage'=>$room['stage'],'elapsed'=>$room['world']['elapsed']??0,'saved'=>$room['world']!==null,
        'member'=>isset($room['players'][$slot]),'admin'=>$room['players'][$room['host']]['digest']===$digest];
    $reply=['ok'=>true,'ack'=>$user['seq'],'poll_ms'=>$config['poll_ms'],'mode'=>'directory',
        'directory'=>['rooms'=>$directory,'browse'=>true,'status'=>'Комнаты: '.count($directory).' / '.$config['max_rooms']]];
    if ($user['room']!=='' && isset($state['rooms'][$user['room']])) {
        $room=&$state['rooms'][$user['room']];
        if (!isset($room['players'][$slot])) { $user['room']=''; $reply['error']='Администратор удалил ваше место.'; return $reply; }
        $reply['mode']=$room['stage']; $players=[]; $pings=[];
        foreach ($room['players'] as $id=>$p) {
            if ($room['stage']==='lobby' && !$p['bot'] && $p['connected'] && isset($p['ping_ms'],$p['ping_at']) && $room['time']-$p['ping_at']<=12)
                $pings[$id]=$p['ping_ms'];
            unset($p['digest'],$p['seen'],$p['ping_ms'],$p['ping_at']); $players[$id]=$p;
        }
        if ($room['stage']==='lobby') $reply['pings']=(object)$pings;
        $reply['lobby']=['players'=>(object)$players,'slot'=>$slot,'host'=>$room['host'],'name'=>$room['name'],'room'=>$user['room'],
            'stage'=>$room['stage'],'status'=>$room['status'],'port'=>443,'resuming'=>$room['world']!==null,
            'homes_locked'=>$room['world']===null?[]:array_keys($room['world']['factions']),
            'occupied'=>$room['world']===null?[]:array_keys(array_filter($room['world']['owners'],fn($id)=>$id!==''))];
        if ($room['stage']==='game') {
            $reply['view']=$sim->view($room['world'],$slot,$room['players']);
            $room['world']['factions'][$slot]['sounds']=[]; $room['world']['factions'][$slot]['effects']=[];
        }
    }
    return $reply;
}
function atlas_api(array &$state,array $request,array $config,int $now): array {
    $sim=new AtlasWorld();
    foreach ($state['rooms'] as &$room) atlas_advance($room,$now,$config,$sim);
    unset($room);
    $action=$request['action']??null;
    if (!is_string($action) || strlen($action)>20) throw new DomainException('Неверный запрос.');
    if ($action==='connect') {
        $token=$request['token']??''; $nonce=$request['nonce']??''; $name=$request['name']??'';
        if (!is_string($token) || !preg_match('/^[a-f0-9]{48}$/D',$token) || !is_string($nonce) || !preg_match('/^[a-f0-9]{32}$/D',$nonce) || !is_string($name) || strlen($name)>96 || ($request['protocol']??null)!==5) throw new DomainException('Несовместимый клиент.');
        $mods=$request['mods']??[];
        if (!is_array($mods) || !array_is_list($mods) || count($mods)>32 || count(array_unique($mods,SORT_REGULAR))!==count($mods)) throw new DomainException('Invalid mod profile');
        foreach ($mods as $hash) if (!atlas_mod_hash($hash)) throw new DomainException('Invalid mod hash');
        $digest=hash('sha256',$token);
        foreach ($state['users'] as $id=>$user) {
            if ($now-$user['seen']>3600) { unset($state['users'][$id]); continue; }
            if ($user['digest']!==$digest) continue;
            if ($user['nonce']===$nonce) {
                if ($user['room']!=='' && ($user['mods']??[])!==$mods) throw new DomainException('Leave the room before changing mods');
                $state['users'][$id]['mods']=$mods;
                $reply=atlas_response($state,$id,$config,$sim); $reply['session']=$id; return $reply; }
            if ($now-$user['seen']<=$config['lease_seconds']) throw new DomainException('Этот профиль уже подключён.');
        }
        if (count($state['users'])>=128) throw new DomainException('Слишком много подключений.');
        $session=bin2hex(random_bytes(32));
        $state['users'][$session]=['digest'=>$digest,'name'=>atlas_name($name),'nonce'=>$nonce,'room'=>'','seen'=>$now,'seq'=>0,'rate_time'=>$now,'rate'=>0,'error'=>'','mods'=>$mods];
        $reply=atlas_response($state,$session,$config,$sim); $reply['session']=$session; return $reply;
    }
    $session=$request['session']??'';
    if (!is_string($session) || !isset($state['users'][$session])) throw new UnexpectedValueException('Подключение истекло. Войдите снова.');
    $user=&$state['users'][$session]; $slot='p_'.substr($user['digest'],0,16);
    if ($user['rate_time']!==$now) { $user['rate_time']=$now; $user['rate']=0; }
    if (++$user['rate']>15) throw new DomainException('Слишком много запросов.');
    $user['seen']=$now;
    if ($action==='disconnect') {
        if (isset($state['rooms'][$user['room']])) atlas_offline($state['rooms'][$user['room']],$slot);
        unset($state['users'][$session]); return ['ok'=>true];
    }
    if (isset($state['rooms'][$user['room']]['players'][$slot])) {
        $player=&$state['rooms'][$user['room']]['players'][$slot]; $player['seen']=$now;
        if (!$player['connected']) { $player['connected']=true; $player['ready']=false; }
        $ping=$request['ping_ms']??null;
        if ($action==='poll' && $state['rooms'][$user['room']]['stage']==='lobby' && is_int($ping) && $ping>=0 && $ping<=8000) {
            $player['ping_ms']=$ping; $player['ping_at']=$now;
        }
        unset($player);
    }
    if ($action==='poll') return atlas_response($state,$session,$config,$sim);
    $seq=$request['seq']??null; $args=$request['args']??[];
    if (!is_int($seq) || $seq<1 || !is_array($args) || !array_is_list($args) || count($args)>2) throw new DomainException('Неверная команда.');
    if ($seq<=$user['seq']) { $reply=atlas_response($state,$session,$config,$sim); if ($seq===$user['seq'] && $user['error']!=='') $reply['error']=$user['error']; return $reply; }
    if ($seq!==$user['seq']+1) throw new DomainException('Неверная последовательность команд.');
    $user['seq']=$seq; $user['error']='';
    if (in_array($action,['join','create'],true) && ($user['mods']??[])!==atlas_mod_hashes()) {
        $reply=atlas_response($state,$session,$config,$sim); $reply['mod_offer']=atlas_mod_profile(); return $reply;
    }
    try {
        if ($action==='leave') {
            if (isset($state['rooms'][$user['room']])) atlas_offline($state['rooms'][$user['room']],$slot);
            $user['room']='';
        } elseif ($action==='game') {
            if (!isset($state['rooms'][$user['room']]) || !is_string($request['command']??null)) throw new DomainException('Войдите в комнату.');
            atlas_lobby_action($state['rooms'][$user['room']],$slot,$request['command'],$args,$now,$sim);
        } elseif ($user['room']!=='') throw new DomainException('Сначала покиньте комнату.');
        elseif ($action==='create') {
            if (count($state['rooms'])>=$config['max_rooms']) throw new DomainException('Сервер заполнен. Удалите свою старую комнату.');
            if (count($args)!==1 || !is_string($args[0]) || strlen($args[0])>160) throw new DomainException('Неверное название.');
            $id=bin2hex(random_bytes(8));
            $room=['name'=>atlas_name($args[0],40),'host'=>$slot,'players'=>[],'banned'=>[],'world'=>null,'stage'=>'lobby','time'=>$now,'status'=>'Комната работает на PHP-хостинге.'];
            $room['players'][$slot]=atlas_player($room,$user['digest'],$user['name'],false,$now);
            $state['rooms'][$id]=$room; $user['room']=$id;
        } elseif (in_array($action,['join','delete'],true)) {
            $id=$args[0]??null;
            if (!is_string($id) || !isset($state['rooms'][$id])) throw new DomainException('Комната не найдена.');
            $room=&$state['rooms'][$id];
            if ($action==='delete') {
                if ($room['players'][$room['host']]['digest']!==$user['digest']) throw new DomainException('Нужны права администратора.');
                foreach ($room['players'] as $p) if ($p['connected'] && !$p['bot']) throw new DomainException('Сначала все игроки должны выйти.');
                unset($state['rooms'][$id]);
            } else {
                if (in_array($user['digest'],$room['banned'],true)) throw new DomainException('Ваше место было удалено.');
                if (!isset($room['players'][$slot])) {
                    if (count($room['players'])>=atlas_start_country_count()) throw new DomainException('Комната заполнена.');
                    $room['players'][$slot]=atlas_player($room,$user['digest'],$user['name'],false,$now);
                } else { $room['players'][$slot]['connected']=true; $room['players'][$slot]['seen']=$now; }
                $user['room']=$id; atlas_pause($room,'Игрок подключился. Подтвердите готовность.');
            }
            unset($room);
        } else throw new DomainException('Неизвестная команда.');
    } catch (DomainException $error) { $user['error']=$error->getMessage(); }
    $reply=atlas_response($state,$session,$config,$sim);
    if ($user['error']!=='') $reply['error']=$user['error'];
    return $reply;
}
