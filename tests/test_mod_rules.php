<?php
declare(strict_types=1);
require $argv[1].'/simulation.php';
$fixtures=json_decode(file_get_contents($argv[2]),true,64,JSON_THROW_ON_ERROR);
$sim=new AtlasWorld(); $world=$sim->create(); $world['random_state']=2026;
$sim->add($world,'a',0,'69dfbd'); $sim->add($world,'b',1,'73aeef');
$checks=0;
foreach ($fixtures as $fixture) {
    [$action,$args]=$fixture['action'];
    if ($action==='reset') { $world=$sim->create();$world['random_state']=2026;$sim->add($world,'a',0,'69dfbd');$sim->add($world,'b',1,'73aeef'); }
    elseif ($action==='tick'||$action==='bot_tick') for($i=0;$i<$args[0];$i++) $sim->tick($world,$action==='bot_tick'?['a','b']:[]);
    elseif (!$sim->command($world,'a',$action,$args)) throw new RuntimeException('Command rejected: '.$action);
    $actual=['random_state'=>$world['random_state'],'bot_profiles'=>$world['bot_profiles'],'elapsed'=>$world['elapsed'],'owners'=>$world['owners'],'countries'=>$world['countries'],'states'=>[]];
    foreach ($world['factions'] as $slot=>$g) {
        $income=mr_extra_income($world,$slot);
        foreach ($world['owners'] as $id=>$owner) if ($owner===$slot) $income+=array_sum($world['countries'][$id]['businesses']);
        $actual['states'][$slot]=['coins'=>$g['coins'],'units'=>$g['units'],'levels'=>$g['levels'],'mod_state'=>$g['mod_state'],'income'=>$income];
    }
    unset($fixture['action']);
    // Empty PHP associative arrays encode as []; compare decoded data recursively.
    if ($fixture!=$actual) {
        echo json_encode(['expected'=>$fixture,'actual'=>$actual],JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE);
        throw new RuntimeException('Godot/PHP portable rules diverged at '.$action);
    }
    $checks++;
}
echo "PASS: $checks Godot/PHP content, research, buildings, events, combat and objectives snapshots\n";
