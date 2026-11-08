<?php
declare(strict_types=1);

function mr_content(): array { return atlas_mod_composed()['content']; }
function mr_unit_ids(): array { return ['infantry','aircraft','navy',...array_column(mr_content()['units'],'id')]; }
function mr_state(array &$g): void {
    if (empty($g['mod_state'])) $g['mod_state']=['fired'=>[],'flags'=>[],'researches'=>[],'random_state'=>71+max($g['home'],0)*319,'hold_since'=>-1,'result'=>''];
}
function mr_start_territories(int $home): array { return array_values(array_unique([$home,...(mr_content()['scenario']['starts'][(string)$home]['owned']??[])])); }
function mr_requirements(array $g,array $ids): bool { return !array_diff($ids,$g['mod_state']['researches']??[]); }
function mr_unit_available(array $g,int $index): bool { return $index<3||mr_requirements($g,mr_content()['units'][$index-3]['requires']??[]); }
function mr_unit_bonus(array $g,int $index): float {
    $bonus=0; $id=mr_unit_ids()[$index];
    foreach (mr_content()['technologies'] as $t) if (($t['unit']??'infantry')===$id&&in_array($t['id'],$g['mod_state']['researches']??[],true)) $bonus+=$t['bonus']??0;
    return (float)$bonus;
}
function mr_extra_income(array $w,string $slot): int {
    $total=0; $g=$w['factions'][$slot];
    foreach ($w['owners'] as $id=>$owner) if ($owner===$slot) foreach (mr_content()['buildings'] as $b) $total+=$b['income']*($w['countries'][$id]['structures'][$b['id']]??0);
    foreach (mr_content()['technologies'] as $t) if (in_array($t['id'],$g['mod_state']['researches']??[],true)) $total+=$t['income']??0;
    return $total;
}
function mr_allied(int $a,int $b): bool {
    foreach (mr_content()['scenario']['alliances']??[] as $group) if (in_array($a,$group,true)&&in_array($b,$group,true)) return true;
    return false;
}
function mr_start(array &$w,string $slot,callable $message): void {
    $g=&$w['factions'][$slot]; mr_state($g);
    $start=mr_content()['scenario']['starts'][(string)$g['home']]??[];
    foreach (['coins','units','levels'] as $key) if (isset($start[$key])) $g[$key]=$start[$key];
    $g['mod_state']['researches']=$start['researches']??[];
    foreach (mr_start_territories($g['home']) as $id) $w['owners'][$id]=$slot;
    mr_emit($w,$slot,'start',$g['home'],$message);
}
function mr_construct(array &$w,string $slot,int $country,int $index,callable $message,?int $time=null): bool {
    $item=mr_content()['buildings'][$index]??null; $g=&$w['factions'][$slot];
    if (!$item||($w['owners'][$country]??null)!==$slot||!mr_requirements($g,$item['requires']??[])) return false;
    $level=$w['countries'][$country]['structures'][$item['id']]??0; $cost=$item['cost']*($level+1);
    if ($level>=1000000||$g['coins']<$cost) return false;
    $g['coins']-=$cost; $w['countries'][$country]['structures'][$item['id']]=$level+1;
    mr_emit($w,$slot,'building_built',$country,$message,$time);
    return true;
}
function mr_research(array &$w,string $slot,int $index,callable $message,?int $time=null): bool {
    $t=mr_content()['technologies'][$index]??null; $g=&$w['factions'][$slot];
    if (!$t||in_array($t['id'],$g['mod_state']['researches']??[],true)||$g['coins']<$t['cost']||!mr_requirements($g,$t['requires']??[])) return false;
    mr_state($g); $g['coins']-=$t['cost']; $g['mod_state']['researches'][]=$t['id'];
    mr_emit($w,$slot,'research_completed',$g['home'],$message,$time);
    return true;
}
function mr_emit(array &$w,string $slot,string $trigger,int $country,callable $message,?int $time=null): void {
    $clock=$time??$w['elapsed'];
    $g=&$w['factions'][$slot]; $definitions=mr_content()['events'];
    if (!$definitions) return;
    mr_state($g); $budget=64;
    foreach ($definitions as $e) {
        if ($e['when']!==$trigger) continue;
        if (isset($g['mod_state']['fired'][$e['id']])&&(($e['once']??true)||$clock-$g['mod_state']['fired'][$e['id']]<($e['cooldown']??1))) continue;
        $c=$e['conditions']??[];
        if (isset($c['country_id'])&&$c['country_id']!==$country) continue;
        if ($clock<($c['elapsed_min']??0)||$g['coins']<($c['coins_min']??0)||!mr_requirements($g,$c['researches']??[])) continue;
        foreach ($c['owns']??[] as $id) if ($w['owners'][$id]!==$slot) continue 2;
        foreach ($c['flags']??[] as $key=>$value) if (($g['mod_state']['flags'][$key]??null)!==$value) continue 2;
        if (($c['chance']??100)<100) {
            $g['mod_state']['random_state']=($g['mod_state']['random_state']*48271)%2147483647;
            if ($g['mod_state']['random_state']%100>=$c['chance']) continue;
        }
        if (count($e['actions'])>$budget) break;
        $budget-=count($e['actions']); $g['mod_state']['fired'][$e['id']]=$clock;
        foreach ($e['actions'] as $a) {
            switch ($a['type']) {
                case 'add_coins': $g['coins']=max(0,min(1e12,$g['coins']+($a['amount']??0))); break;
                case 'add_units': $index=array_search($a['unit']??'infantry',mr_unit_ids(),true); $g['units'][$index]=max(0,min(100000000,$g['units'][$index]+($a['amount']??0))); break;
                case 'show_message': $message($slot,$a['text']??''); break;
                case 'set_flag': $g['mod_state']['flags'][$a['key']]=$a['value']; break;
                case 'grant_research': if (!in_array($a['technology'],$g['mod_state']['researches'],true)) $g['mod_state']['researches'][]=$a['technology']; break;
                case 'capture_country': $w['owners'][$a['country_id']]=$slot; break;
                case 'release_country': if ($w['owners'][$a['country_id']]===$slot) $w['owners'][$a['country_id']]=''; break;
                case 'win': case 'lose': $g['mod_state']['result']=$a['type']; break;
            }
        }
        if ($g['mod_state']['result']!=='') break;
    }
}
function mr_victory(array $w,string $slot): ?bool {
    $g=$w['factions'][$slot]; $state=$g['mod_state']??[];
    if (($state['result']??'')!=='') return $state['result']==='win';
    $goal=mr_content()['victory'];
    switch ($goal['type']??'world') {
        case 'coins': return $g['coins']>=$goal['amount'];
        case 'countries': foreach ($goal['countries'] as $id) if ($w['owners'][$id]!==$slot) return false; return true;
        case 'hold': return ($state['hold_since']??-1)>=0&&$w['elapsed']-$state['hold_since']>=$goal['seconds'];
        case 'time': return $w['elapsed']>=$goal['seconds'];
    }
    return null;
}
function mr_tick(array &$w,string $slot,callable $message): void {
    $goal=mr_content()['victory']; $g=&$w['factions'][$slot];
    if (($goal['type']??'')==='hold') {
        mr_state($g); $owned=true;
        foreach ($goal['countries'] as $id) if ($w['owners'][$id]!==$slot) $owned=false;
        if (!$owned) $g['mod_state']['hold_since']=-1;
        elseif ($g['mod_state']['hold_since']<0) $g['mod_state']['hold_since']=$w['elapsed'];
    }
    mr_emit($w,$slot,'tick',-1,$message);
    if (!in_array($slot,$w['owners'],true)) { mr_state($g); $g['mod_state']['result']='lose'; }
    if (mr_victory($w,$slot)===true&&($g['mod_state']['result']??'')==='') { mr_state($g); $g['mod_state']['result']='win'; if (count($g['sounds'])<40) $g['sounds'][]='campaign_win'; }
}
