<?php
declare(strict_types=1);

final class AtlasWorld {
    private array $map;
    private array $b;
    private ?int $commandTime = null;
    public function __construct() {
        $this->b = json_decode(file_get_contents(__DIR__.'/balance.json'), true, 32, JSON_THROW_ON_ERROR);
        $this->map = json_decode(file_get_contents(__DIR__.'/data.json'), true, 64, JSON_THROW_ON_ERROR);
    }
    public function create(): array {
        return ['rules_version'=>$this->b['version'], 'elapsed'=>0, 'countries'=>$this->map['countries'], 'owners'=>array_fill(0,176,''), 'factions'=>[], 'occupations'=>[], 'bot_profiles'=>[], 'random_state'=>random_int(1,2147483646)];
    }
    public function add(array &$w, string $slot, int $home, string $color): void {
        if ($w['owners'][$home] !== '') throw new DomainException('Страна уже занята.');
        $w['owners'][$home]=$slot;
        $w['factions'][$slot]=['home'=>$home,'coins'=>$this->b['start_coins'],'units'=>$this->b['start_units'],'levels'=>[1,1,1],
            'mission'=>[], 'reports'=>[], 'events'=>[], 'player_color'=>$color, 'campaign_id'=>'php_'.$slot,
            'operations'=>[], 'conquests'=>[], 'nukes'=>0, 'victories'=>0,'defeats'=>0,
            'notification_serial'=>0,'notifications_seen'=>0,'sounds'=>['start'],'effects'=>[], 'wars'=>[], 'battles'=>[]];
        $this->event($w,$slot,'Поднят ваш флаг: '.$this->name($home).'. История начинается.');
    }
    public function remove(array &$w, string $slot): void {
        if (!isset($w['factions'][$slot])) return;
        $count=max(1,count(array_filter($w['owners'],fn($owner)=>$owner===$slot)));
        foreach ($w['owners'] as $id=>$owner) if ($owner===$slot) {
            $w['countries'][$id]['units']=array_map(fn($n)=>intdiv($n,$count),$w['factions'][$slot]['units']);
            $w['owners'][$id]='';
        }
        unset($w['factions'][$slot],$w['bot_profiles'][$slot]);
        foreach ($w['occupations']??[] as $key=>$entry) if ($entry['previous']===$slot || $entry['owner']===$slot) unset($w['occupations'][$key]);
    }
    private function name(int $id): string { return $this->map['atlas'][$id]['name']; }
    private function rebel(int $id): bool { return $id%3===0 && $this->power($this->map['countries'][$id]['units'])>=300; }
    private function roll(array &$w,int $limit=100): int {
        $w['random_state']=(($w['random_state']??1)*48271)%2147483647;
        return $w['random_state']%$limit;
    }
    private function war(array &$w,string $slot,int $id): void {
        if (!in_array($id,$w['factions'][$slot]['wars']??[],true)) $w['factions'][$slot]['wars'][]=$id;
    }
    private function declareWar(array &$w,string $slot,int $id,bool $surprise): void {
        $this->war($w,$slot,$id);
        $owner=$w['owners'][$id];
        if ($owner==='' || $owner===$slot) return;
        if ($surprise) {
            $index=array_key_last($w['factions'][$slot]['operations']);
            $w['factions'][$slot]['operations'][$index]['surprise']=true;
            return;
        }
        $origin=$this->origin($w,$slot,$id);
        $this->war($w,$owner,$origin);
        $this->event($w,$owner,$this->name($origin).' объявляет вам войну! Цель наступления: '.$this->name($id).'.');
        $this->cue($w,$owner,'warning');
    }
    public function power(array $army, array $levels=[1,1,1]): float {
        $power=0;
        foreach ($this->b['unit_weight'] as $i=>$weight) $power += $army[$i]*$weight*(1+($levels[$i]-1)*$this->b['technology_bonus']);
        return $power;
    }
    private function event(array &$w,string $slot,string $text): void {
        $g=&$w['factions'][$slot];
        $g['notification_serial']++;
        array_unshift($g['events'],['time'=>$this->commandTime??$w['elapsed'],'text'=>$text]);
        $g['events']=array_slice($g['events'],0,40);
    }
    private function cue(array &$w,string $slot,string $sound,?int $target=null,?string $effect=null): void {
        $g=&$w['factions'][$slot];
        if (count($g['sounds'])<40) $g['sounds'][]=$sound;
        if ($effect!==null && count($g['effects'])<40) $g['effects'][]=['kind'=>$effect,'target'=>$target];
    }
    private function alive(array $w,string $slot): bool {
        return in_array($slot,$w['owners'],true) && count(array_unique($w['owners']))>1;
    }
    private function border(array $w,string $slot,int $id): bool {
        foreach ($this->map['atlas'][$id]['neighbors'] as $n) if ($w['owners'][$n]===$slot) return true;
        return false;
    }
    private function origin(array $w,string $slot,int $target): int {
        foreach ($this->map['atlas'][$target]['neighbors'] as $id) if ($w['owners'][$id]===$slot) return (int)$id;
        $home=$w['factions'][$slot]['home'];
        return $w['owners'][$home]===$slot ? $home : (int)array_search($slot,$w['owners'],true);
    }
    private function army(array $w,int $id): array {
        $owner=$w['owners'][$id];
        return $owner==='' ? $w['countries'][$id]['units'] : $w['factions'][$owner]['units'];
    }
    private function has(array $g,string $kind): bool {
        return count(array_filter($g['operations'],fn($op)=>$op['kind']===$kind))>0;
    }
    private function attackable(array $w,string $slot,int $id): bool {
        $g=$w['factions'][$slot];
        $land=$this->border($w,$slot,$id);
        return $w['owners'][$id]!==$slot && !$this->has($g,'attack') && ($land || $g['units'][2]>=$this->b['naval_ships'])
            && $this->power($g['units'],$g['levels'])>=1 && $g['coins']>=($land?$this->b['attack_cost']:$this->b['naval_cost']);
    }
    public function command(array &$w,string $slot,string $action,array $args,bool $surprise=false): bool {
        if (!isset($w['factions'][$slot]) || !$this->alive($w,$slot) || count($args)>2) return false;
        foreach ($args as $arg) if (!is_int($arg) || $arg<0 || $arg>=176) return false;
        $g=&$w['factions'][$slot];
        $i=$args[0]??-1;
        if ($action==='read' && !$args) { $g['notifications_seen']=$g['notification_serial']; return true; }
        if (in_array($action,['recruit','upgrade'],true) && count($args)===1 && $i<3) {
            $cost=$action==='recruit'?$this->b['unit_cost'][$i]:$this->b['technology_cost']*$g['levels'][$i];
            if ($g['coins']<$cost || $g['units'][$i]>99999980 || $g['levels'][$i]>=1000000) return false;
            $g['coins']-=$cost;
            if ($action==='recruit') $g['units'][$i]+=$this->b['recruit_units'][$i];
            else {
                $g['levels'][$i]++;
                $this->event($w,$slot,['Пехота','Авиация','Флот'][$i].': технология уровня '.$g['levels'][$i].'.');
            }
            $this->cue($w,$slot,$action==='recruit'?'coins':'upgrade'); return true;
        }
        if ($action==='business' && count($args)===2 && $w['owners'][$i]===$slot) {
            $j=$args[1];
            if (!isset($w['countries'][$i]['businesses'][$j])) return false;
            $level=&$w['countries'][$i]['businesses'][$j];
            if ($g['coins']<$this->b['business_cost']*$level || $level>=1000000) return false;
            $g['coins']-=$this->b['business_cost']*$level; $level++; $this->cue($w,$slot,'coins'); return true;
        }
        if (count($args)!==1 || $w['owners'][$i]===$slot) return false;
        $time=$this->commandTime??$w['elapsed'];
        $op=['target'=>$i,'from'=>$this->origin($w,$slot,$i),'start'=>$time];
        if ($action==='spy' && !$g['mission'] && $g['coins']>=$this->b['spy_cost']) {
            $g['coins']-=$this->b['spy_cost']; $op['arrival']=$time+$this->b['spy_seconds']; $g['mission']=$op;
            $this->event($w,$slot,'Агент направлен: '.$this->name($i).'. Отчёт через '.$this->b['spy_seconds'].' секунд.');
            $this->cue($w,$slot,'spy_send'); return true;
        }
        if ($action==='attack' && $this->attackable($w,$slot,$i)) {
            $land=$this->border($w,$slot,$i); $g['coins']-=$land?$this->b['attack_cost']:$this->b['naval_cost'];
            $op+=['kind'=>'attack','arrival'=>$time+$this->b['attack_seconds'],'overseas'=>!$land]; $g['operations'][]=$op;
            $this->declareWar($w,$slot,$i,$surprise);
            $this->event($w,$slot,'Армия выдвинулась: '.$this->name($i).'. Прибытие через '.$this->b['attack_seconds'].' секунд.');
            $this->cue($w,$slot,$land?'march':'march_naval'); return true;
        }
        if ($action==='nuke' && $g['nukes']>0 && !$this->has($g,'nuke')) {
            $g['nukes']--; $op+=['kind'=>'nuke','arrival'=>$time+$this->b['nuke_seconds']]; $g['operations'][]=$op;
            $this->event($w,$slot,'Ядерная ракета запущена: '.$this->name($i).'. Подлёт — '.$this->b['nuke_seconds'].' секунд.');
            $this->cue($w,$slot,'rocket_launch'); return true;
        }
        return false;
    }
    private function resolve(array &$w,string $slot,array $op): void {
        $w['factions'][$slot]['battles']??=[];
        $id=$op['target']; $owner=$w['owners'][$id]; $g=&$w['factions'][$slot];
        if ($owner===$slot) {
            if ($op['kind']==='nuke') { $g['nukes']++; $this->event($w,$slot,'Ядерный удар отменён: цель уже ваша. Заряд возвращён.'); }
            return;
        }
        $this->war($w,$slot,$id);
        if ($owner!=='') {
            $this->war($w,$owner,$op['from']);
            if ($op['surprise']??false) $this->event($w,$owner,'Внезапное нападение на '.$this->name($id).'!');
        }
        if ($owner==='') $defender=&$w['countries'][$id]['units'];
        else $defender=&$w['factions'][$owner]['units'];
        if ($op['kind']==='nuke') {
            foreach ($defender as &$n) $n=(int)floor($n*0.5);
            unset($n);
            $text='Ядерный удар по '.$this->name($id).': армия потеряла 50% состава.';
            $this->event($w,$slot,$text); $this->cue($w,$slot,'nuke',$id,'nuke');
            if ($owner!=='') { $this->event($w,$owner,$text); $this->cue($w,$owner,'nuke',$id,'nuke'); }
            return;
        }
        $this->cue($w,$slot,$op['overseas']?'battle_naval':'battle');
        $attackers=$g['units']; $defenders=$defender;
        $attackLevels=$g['levels']; $defenseLevels=$owner===''?[1,1,1]:$w['factions'][$owner]['levels']; $support=0;
        $effective=$this->power($g['units'],$g['levels'])*($op['overseas']?$this->b['naval_multiplier']:1);
        $defense=$this->power($defender,$owner===''?[1,1,1]:$w['factions'][$owner]['levels']);
        if ($this->rebel($id)) {
            $support=$this->roll($w,10)+1;
            $defense*=1-$support/100;
            $this->event($w,$slot,'Повстанцы в '.$this->name($id).' помогли наступлению: сила обороны снижена на '.$support.'%.');
        }
        $won=$effective>=$defense;
        $loss=max($this->b['attack_loss_min'],min($this->b['attack_loss_max'],$defense/max(1,$effective)*$this->b['attack_loss']));
        foreach ($g['units'] as &$n) $n=max(0,$n-(int)ceil($n*$loss));
        unset($n);
        if ($won) {
            $g['victories']++; $g['coins']=min(1e12,$g['coins']+$this->b['loot']); $w['owners'][$id]=$slot;
            if ($this->rebel($id)) $w['occupations'][(string)$id]=['previous'=>$owner,'owner'=>$slot,'due'=>$w['elapsed']+120+$this->roll($w,301)];
            if ($id!==$g['home'] && !in_array($id,$g['conquests'],true)) {
                $g['conquests'][]=$id;
                if (count($g['conquests'])%$this->b['nuclear_threshold']===0) { $g['nukes']++; $this->cue($w,$slot,'unlock'); }
            }
            $this->event($w,$slot,'Победа! '.$this->name($id).' под вашим контролем. Трофеи: 30 монет.');
            if ($owner!=='') {
                foreach ($defender as &$n) $n=max(0,$n-(int)ceil($n*$this->b['defender_retreat_loss']));
                unset($n);
                $w['factions'][$owner]['defeats']++;
                $this->war($w,$owner,$id);
                $this->event($w,$owner,'Игрок захватил '.$this->name($id).'. Отступившие войска сохранились.');
                $this->cue($w,$owner,'defeat',$id,'defeat');
            }
        } else {
            $g['defeats']++;
            foreach ($defender as &$n) $n=max(0,$n-(int)ceil($n*$this->b['defender_hold_loss']));
            unset($n);
            $this->event($w,$slot,'Отступление из '.$this->name($id).'. Усильте армию перед новой атакой.');
            if ($owner!=='') {
                $w['factions'][$owner]['victories']++;
                $this->event($w,$owner,'Атака на '.$this->name($id).' отбита.');
                $this->cue($w,$owner,'victory',$id,'victory');
            }
        }
        $report=['target'=>$id,'time'=>$w['elapsed'],'attacking'=>true,'won'=>$won,
            'attackers'=>$attackers,'defenders'=>$defenders,'attack_levels'=>$attackLevels,'defense_levels'=>$defenseLevels,
            'effective'=>$effective,'defense'=>$defense,'overseas'=>$op['overseas'],'rebels'=>$support,
            'attack_losses'=>array_map(fn($a,$b)=>$a-$b,$attackers,$g['units']),
            'defense_losses'=>array_map(fn($n)=>(int)ceil($n*($won?($owner===''?1:$this->b['defender_retreat_loss']):$this->b['defender_hold_loss'])),$defenders)];
        array_unshift($g['battles'],$report); $g['battles']=array_slice($g['battles'],0,20);
        if ($owner!=='') {
            $report['attacking']=false; $report['won']=!$won;
            $w['factions'][$owner]['battles']??=[];
            array_unshift($w['factions'][$owner]['battles'],$report);
            $w['factions'][$owner]['battles']=array_slice($w['factions'][$owner]['battles'],0,20);
        }
        $this->cue($w,$slot,$won?($this->alive($w,$slot)?'victory':'campaign_win'):'defeat',$id,$won?'victory':'defeat');
    }
    public function tick(array &$w,array $bots): void {
        if (($w['rules_version']??1)!==$this->b['version']) throw new DomainException('Unsupported game rules version');
        $w['elapsed']++;
        foreach (array_keys($w['factions']) as $slot) {
            $g=&$w['factions'][$slot];
            if (!$this->alive($w,$slot)) { $g['operations']=[]; $g['mission']=[]; continue; }
            if (in_array($slot,$bots,true) && $w['elapsed']%$this->b['bot_seconds']===0) {
                $this->commandTime=$w['elapsed']-1;
                try { $this->bot($w,$slot); } finally { $this->commandTime=null; }
            }
            foreach ($w['owners'] as $id=>$owner) if ($owner===$slot) $g['coins']=min(1e12,$g['coins']+array_sum($w['countries'][$id]['businesses']));
            $operations=$g['operations']; $g['operations']=[];
            foreach ($operations as $op) {
                if ($op['arrival']>$w['elapsed']) $g['operations'][]=$op;
                else {
                    $this->resolve($w,$slot,$op);
                    if (!$this->alive($w,$slot)) { $g['operations']=[]; $g['mission']=[]; break; }
                }
            }
            if ($g['mission'] && $g['mission']['arrival']<=$w['elapsed']) {
                $id=$g['mission']['target']; $g['reports'][(string)$id]=['units'=>$this->army($w,$id),'time'=>$w['elapsed']]; $g['mission']=[];
                $this->event($w,$slot,'Разведка завершена: '.$this->name($id).'. Состав войск раскрыт.'); $this->cue($w,$slot,'report');
            }
            if (in_array($slot,$bots,true)) { $g['effects']=[]; $g['sounds']=[]; }
        }
        if ($w['elapsed']%30===0) foreach ($w['owners'] as $i=>$owner) if ($owner==='') $w['countries'][$i]['units'][0]=min(100000000,$w['countries'][$i]['units'][0]+1);
        foreach ($w['occupations']??[] as $key=>$entry) {
            $id=(int)$key;
            if ($w['owners'][$id]!==$entry['owner']) { unset($w['occupations'][$key]); continue; }
            if ($w['elapsed']<$entry['due']) continue;
            $w['occupations'][$key]['due']=$w['elapsed']+120+$this->roll($w,301);
            if ($this->roll($w)>=20) continue;
            $former=$entry['previous'];
            if ($former!=='' && !isset($w['factions'][$former])) $former='';
            $w['owners'][$id]=$former;
            $this->war($w,$entry['owner'],$id);
            $this->event($w,$entry['owner'],'Повстанцы вернули '.$this->name($id).' прежнему владельцу.');
            $this->cue($w,$entry['owner'],'defeat');
            if ($former!=='') { $this->event($w,$former,'Повстанцы вернули вам '.$this->name($id).'.'); $this->cue($w,$former,'victory'); }
            else $w['countries'][$id]['units']=[10,0,0];
            unset($w['occupations'][$key]);
        }
    }
    private function bot(array &$w,string $slot): void {
        $g=&$w['factions'][$slot];
        if (!isset($w['bot_profiles'][$slot])) {
            do { $candidate=['style'=>$this->roll($w,3),'risk'=>70+$this->roll($w,41),'economy'=>15+$this->roll($w,51),'branch'=>$this->roll($w,3)]; }
            while (in_array($candidate,$w['bot_profiles']??[],true));
            $w['bot_profiles'][$slot]=$candidate;
        }
        $p=$w['bot_profiles'][$slot];
        $invest=$this->roll($w)<$p['economy']+($p['style']===0?$this->b['bot_economy_bonus']:0); $improved=false;
        if ($invest) {
            $cheapest=INF; $country=-1; $business=-1;
            foreach ($w['owners'] as $id=>$owner) {
                if ($owner!==$slot) continue;
                foreach ($w['countries'][$id]['businesses'] as $j=>$level) {
                    $cost=$this->b['business_cost']*$level;
                    if ($cost<$cheapest) { $cheapest=$cost; $country=$id; $business=$j; }
                }
            }
            if ($country>=0) $improved=$this->command($w,$slot,'business',[$country,$business]);
        }
        if (!$improved) {
            $branch=$p['branch'];
            if ($g['units'][2]<$this->b['naval_ships']) $this->command($w,$slot,'recruit',[2]);
            elseif ($g['coins']>=$this->b['bot_upgrade_coins'] && $g['levels'][$branch]<$this->b['bot_max_level']) $this->command($w,$slot,'upgrade',[$branch]);
            else $this->command($w,$slot,'recruit',[$this->roll($w)<$this->b['bot_favorite_chance']?$branch:$this->roll($w,3)]);
        }
        if ($this->has($g,'attack')) return;
        $target=-1; $weakest=INF;
        $threshold=($p['risk']+($p['style']===1?$this->b['bot_style_risk']:($p['style']===2?-$this->b['bot_style_risk']:0)))/100;
        foreach ($w['owners'] as $id=>$owner) {
            if ($owner===$slot || !$this->attackable($w,$slot,$id)) continue;
            $defense=$this->power($this->army($w,$id),$owner===''?[1,1,1]:$w['factions'][$owner]['levels']);
            $strength=$this->power($g['units'],$g['levels'])*($this->border($w,$slot,$id)?1:$this->b['naval_multiplier']);
            if ($defense<=$strength*$threshold && $defense<$weakest) { $target=$id; $weakest=$defense; }
        }
        if ($target>=0) {
            if (!isset($g['reports'][(string)$target])) $this->command($w,$slot,'spy',[$target]);
            if ($this->attackable($w,$slot,$target)) $this->command($w,$slot,'attack',[$target],$this->roll($w)<$this->b['surprise_chance']);
        }
    }
    public function view(array $w,string $slot,array $players): array {
        $g=$w['factions'][$slot]; $countries=$w['countries']; $colors=[]; $names=[]; $remote=[];
        foreach ($w['owners'] as $id=>$owner) {
            $countries[$id]['owned']=$owner===$slot;
            $countries[$id]['units']=$owner===$slot?$g['units']:[0,0,0];
            if ($owner!=='' && isset($players[$owner])) { $colors[(string)$id]=$players[$owner]['color']; $names[(string)$id]=$players[$owner]['name']; }
        }
        foreach ($w['factions'] as $other=>$faction) if ($other!==$slot) foreach ($faction['operations'] as $op) {
            if ($op['surprise']??false) continue;
            $op['kind']=$op['kind']==='nuke'?'nuke':'enemy'; $op['source_color']=$players[$other]['color']; $remote[]=$op;
        }
        $game=$g;
        unset($game['sounds'],$game['effects']);
        $game+=['version'=>3,'elapsed'=>$w['elapsed'],'countries'=>$countries,'warnings'=>[],'military_balance'=>$this->map['balance'],'rules_version'=>$this->b['version'],'battles'=>$g['battles']??[]];
        $game['mission']=(object)$game['mission']; $game['reports']=(object)$game['reports'];
        return ['game'=>$game,'colors'=>(object)$colors,'names'=>(object)$names,'remote'=>$remote,'sounds'=>$g['sounds'],'effects'=>$g['effects']];
    }
}
