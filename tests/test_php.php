<?php
declare(strict_types=1);
require __DIR__.'/../hosting/service.php';
$checks=0;
function check(bool $value,string $text): void {
    global $checks; $checks++;
    if (!$value) throw new RuntimeException('FAIL: '.$text);
}
function parity(mixed $actual,mixed $expected,string $path): void {
    if (is_array($expected)) {
        check(is_array($actual) && count($actual)===count($expected),$path.' shape');
        foreach ($expected as $key=>$value) {
            check(array_key_exists($key,$actual),$path.'.'.$key.' missing');
            parity($actual[$key],$value,$path.'.'.$key);
        }
        return;
    }
    $same=is_numeric($actual) && is_numeric($expected) && (is_float($actual) || is_float($expected))
        ? abs($actual-$expected)<=1e-10*max(1,abs($expected)) : $actual===$expected;
    check($same,$path.' PHP='.json_encode($actual).' Godot='.json_encode($expected));
}
$sim=new AtlasWorld(); $world=$sim->create();
$players=['a'=>['name'=>'A','color'=>'69dfbd'],'b'=>['name'=>'B','color'=>'73aeef']];
foreach (json_decode(file_get_contents(__DIR__.'/../build/php-fixtures.json'),true,128,JSON_THROW_ON_ERROR) as $index=>$fixture) {
    $a=$fixture['action'];
    switch ($a[0]) {
        case 'init': $world['random_state']=$a[1]; $sim->add($world,'a',0,'69dfbd'); $sim->add($world,'b',1,'73aeef'); break;
        case 'reset': $world=$sim->create(); $world['random_state']=$a[1]; $sim->add($world,'a',1,'69dfbd'); $sim->add($world,'b',3,'73aeef'); break;
        case 'army': $world['factions'][$a[1]]['units']=array_slice($a,2); break;
        case 'command': check($sim->command($world,$a[1],$a[2],array_slice($a,3)),'Fixture command '.$index); break;
        case 'tick': for($i=0;$i<$a[1];$i++)$sim->tick($world,[]); break;
        case 'add': $sim->add($world,$a[1],$a[2],$a[3]); $players[$a[1]]=['name'=>'C','color'=>$a[3]]; break;
        case 'nukes': $world['factions']['a']['nukes']=1; $world['factions']['a']['conquests']=range(3,12); break;
        case 'bots': for($i=0;$i<$a[1];$i++)$sim->tick($world,[$a[2]]); break;
        case 'remove': $sim->remove($world,$a[1]); unset($players[$a[1]]); break;
        case 'session':
            $world=$sim->create(); $world['random_state']=$a[1]; $players=[];
            for ($i=0;$i<4;$i++) { $slot='bot'.$i; $sim->add($world,$slot,$i*37,'69dfbd'); $players[$slot]=['name'=>$slot,'color'=>'69dfbd']; }
            break;
        case 'all_bots': for($i=0;$i<$a[1];$i++)$sim->tick($world,array_keys($players)); break;
        case 'roundtrip': $world=json_decode(json_encode($world,JSON_THROW_ON_ERROR),true,128,JSON_THROW_ON_ERROR); break;
    }
    if($world['owners']!==$fixture['owners'])foreach($world['owners'] as $id=>$owner)if($owner!==$fixture['owners'][$id])echo "Ownership diff $id: PHP=$owner Godot=".$fixture['owners'][$id]."\n";
    check($world['elapsed']===$fixture['elapsed'] && $world['owners']===$fixture['owners'],'Godot ownership/clock parity '.$index);
    if($world['random_state']!==$fixture['random_state']) echo 'Random diff '.$index.' PHP '.$world['random_state'].' Godot '.$fixture['random_state'].PHP_EOL;
    check($world['occupations']==$fixture['occupations'] && $world['random_state']===$fixture['random_state'],'Godot rebel timers and random state parity '.$index);
    check(($world['bot_profiles']??[])==$fixture['bot_profiles'],'Godot bot personality parity '.$index);
    foreach ($fixture['states'] as $slot=>$expected) {
        $view=json_decode(json_encode($sim->view($world,$slot,$players),JSON_THROW_ON_ERROR),true);
        foreach ($expected as $key=>$value) {
            parity($view['game'][$key],$value,'Fixture '.$index.' '.json_encode($a).' '.$slot.'.'.$key);
        }
    }
}
$state=['version'=>1,'rooms'=>[],'users'=>[]];
$config=['max_rooms'=>2,'lease_seconds'=>20,'poll_ms'=>1000]; $now=10000;
$a=atlas_api($state,['action'=>'connect','token'=>str_repeat('a',48),'nonce'=>str_repeat('a',32),'name'=>'A','protocol'=>2],$config,$now)['session'];
$b=atlas_api($state,['action'=>'connect','token'=>str_repeat('b',48),'nonce'=>str_repeat('b',32),'name'=>'B','protocol'=>2],$config,$now)['session'];
function request(string $session,string $action,array $args=[],?string $command=null): array {
    global $state,$config,$now;
    $data=['session'=>$session,'action'=>$action,'args'=>$args];
    if($action!=='poll')$data['seq']=$state['users'][$session]['seq']+1;
    if($command!==null)$data['command']=$command;
    return atlas_api($state,$data,$config,$now);
}
$reply=request($a,'create',['Alpha']); $room=$reply['lobby']['room']; $owner=$reply['lobby']['slot'];
check($owner===$reply['lobby']['host'],'Creator is administrator');
request($b,'join',[$room]);
$reply=request($b,'game',[],'bot'); check(isset($reply['error']) && count((array)$reply['lobby']['players'])===2,'Reject foreign administration');
request($a,'game',[true],'ready'); request($b,'game',[true],'ready'); $reply=request($a,'game',[],'start');
check($reply['view']['game']['units']===[35,8,4],'Minimum equal start');
$command=['session'=>$a,'action'=>'game','command'=>'recruit','args'=>[0],'seq'=>$state['users'][$a]['seq']+1];
$first=atlas_api($state,$command,$config,$now); $second=atlas_api($state,$command,$config,$now);
check($first['view']['game']['coins']===$second['view']['game']['coins'] && $second['view']['game']['units'][0]===45,'Retry cannot spend or recruit twice');
check($second['view']['game']['countries'][1]['units']===[0,0,0],'Foreign forces stay private');
$now+=5; $reply=request($b,'poll');
check($reply['view']['game']['elapsed']===5 && $reply['view']['game']['coins']>180,'Request-driven income and clock');
$now+=25;
foreach ($state['rooms'] as &$r) atlas_advance($r,$now,$config,$sim);
unset($r);
check($state['rooms'][$room]['stage']==='lobby' && $state['rooms'][$room]['world']['elapsed']===20,'Cron stops at connection lease instead of granting offline income');
check(!atlas_ready($state['rooms'][$room]),'Disconnected players block resume');
$reply=request($a,'poll');
check($reply['mode']==='lobby','Returning client receives shared pause');
request($b,'poll'); request($a,'game',[true],'ready'); request($b,'game',[true],'ready');
$admin=$state['rooms'][$room]['host']===$owner?$a:$b;
$reply=request($admin,'game',[],'start'); check($reply['mode']==='game','All ready resume');
$departing=$admin; $remaining=$admin===$a?$b:$a;
$departingSlot='p_'.substr($state['users'][$departing]['digest'],0,16);
request($departing,'leave'); $reply=request($remaining,'poll');
check($reply['lobby']['host']===$reply['lobby']['slot'],'Admin transfer');
request($remaining,'game',[$departingSlot],'kick'); $reply=request($departing,'poll');
check($reply['mode']==='directory' && !isset($state['rooms'][$room]['players'][$departingSlot]),'Kicked client has no remaining place');
$reply=request($departing,'join',[$room]); check(isset($reply['error']),'Kick ban persists');
request($remaining,'leave'); request($remaining,'delete',[$room]);
check(!$state['rooms'],'Delete owned room');
$crowded=['host'=>'host','players'=>[],'world'=>null,'stage'=>'lobby'];
$crowded['players']['host']=atlas_player($crowded,'','Host',false,$now);
foreach ([-1,0,1.5,'2',176] as $count) {
    try { atlas_lobby_action($crowded,'host','bot',[$count],$now,$sim); check(false,'Invalid count accepted'); }
    catch (DomainException $error) { check(count($crowded['players'])===1,'Invalid count is atomic'); }
}
atlas_lobby_action($crowded,'host','bot',[175],$now,$sim);
check(count($crowded['players'])===176 && count(array_unique(array_column($crowded['players'],'home')))===176,'Full room has unique countries');
$battle=$sim->create(); $sim->add($battle,'a',0,'69dfbd'); $sim->add($battle,'b',1,'73aeef');
$battle['factions']['a']['units']=[1000,100,100];
check($sim->command($battle,'a','attack',[1],true),'Surprise command accepted');
check(!$sim->view($battle,'b',$players)['remote'] && count($battle['factions']['b']['events'])===1,'Surprise has no advance route or event');
for ($i=0;$i<4;$i++) $sim->tick($battle,[]);
check($battle['owners'][1]==='a' && in_array(1,$battle['factions']['b']['wars'],true),'Surprise marks lost country');
$map=json_decode(file_get_contents(__DIR__.'/../hosting/data.json'),true);
$strong=-1;
foreach ($map['countries'] as $id=>$country) if ($id%3===0 && $sim->power($country['units'])>=300) { $strong=$id; break; }
check($strong>=0,'Strong rebel country exists');
$battle=$sim->create(); $sim->add($battle,'a',1,'69dfbd'); $sim->add($battle,'b',$strong,'73aeef');
$battle['factions']['a']['units']=[1000,100,100];
$sim->command($battle,'a','attack',[$strong]);
check(count($battle['factions']['b']['events'])===2 && in_array(1,$battle['factions']['b']['wars'],true),'Declared war notifies defender and marks origin');
for ($i=0;$i<4;$i++) $sim->tick($battle,[]);
check($battle['owners'][$strong]==='a' && $battle['occupations'][$strong]['previous']==='b','Conquest remembers previous owner');
check($battle['occupations'][$strong]['due']-$battle['elapsed']>=120 && $battle['occupations'][$strong]['due']-$battle['elapsed']<=420,'Uprising uses a random 2 to 7 minute timer');
check(count(array_filter($battle['factions']['a']['events'],fn($event)=>str_contains($event['text'],'%')))===1,'Rebels assist conquest');
$battle=json_decode(json_encode($battle,JSON_THROW_ON_ERROR),true);
$battle['random_state']=1;
while ((($battle['random_state']*48271%2147483647)*48271%2147483647)%100>=20) $battle['random_state']=$battle['random_state']*48271%2147483647;
$battle['occupations'][$strong]['due']=$battle['elapsed']+1;
$sim->tick($battle,[]);
check($battle['owners'][$strong]==='b' && !isset($battle['occupations'][$strong]),'Rebels restore eliminated previous owner after storage roundtrip');
echo "PASS: $checks PHP checks\n";
