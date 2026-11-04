<?php
declare(strict_types=1);
require __DIR__.'/../hosting/service.php';
$checks=0;
function check(bool $value,string $text): void {
    global $checks; $checks++;
    if (!$value) throw new RuntimeException('FAIL: '.$text);
}
$sim=new AtlasWorld(); $world=$sim->create();
$players=['a'=>['name'=>'A','color'=>'69dfbd'],'b'=>['name'=>'B','color'=>'73aeef']];
foreach (json_decode(file_get_contents(__DIR__.'/../build/php-fixtures.json'),true,128,JSON_THROW_ON_ERROR) as $index=>$fixture) {
    $a=$fixture['action'];
    switch ($a[0]) {
        case 'init': $sim->add($world,'a',0,'69dfbd'); $sim->add($world,'b',1,'73aeef'); break;
        case 'command': check($sim->command($world,$a[1],$a[2],array_slice($a,3)),'Fixture command '.$index); break;
        case 'tick': for($i=0;$i<$a[1];$i++)$sim->tick($world,[]); break;
        case 'add': $sim->add($world,$a[1],$a[2],$a[3]); $players[$a[1]]=['name'=>'C','color'=>$a[3]]; break;
        case 'nukes': $world['factions']['a']['nukes']=1; $world['factions']['a']['conquests']=range(3,12); break;
        case 'bots': for($i=0;$i<$a[1];$i++)$sim->tick($world,[$a[2]]); break;
        case 'remove': $sim->remove($world,$a[1]); unset($players[$a[1]]); break;
    }
    if($world['owners']!==$fixture['owners'])foreach($world['owners'] as $id=>$owner)if($owner!==$fixture['owners'][$id])echo "Ownership diff $id: PHP=$owner Godot=".$fixture['owners'][$id]."\n";
    check($world['elapsed']===$fixture['elapsed'] && $world['owners']===$fixture['owners'],'Godot ownership/clock parity '.$index);
    foreach ($fixture['states'] as $slot=>$expected) {
        $view=json_decode(json_encode($sim->view($world,$slot,$players),JSON_THROW_ON_ERROR),true);
        foreach ($expected as $key=>$value) {
            if($view['game'][$key]!=$value && $key!=='countries')echo $key.' PHP '.json_encode($view['game'][$key]).' Godot '.json_encode($value)."\n";
            check($view['game'][$key]==$value,'Godot simulation parity '.$index.' '.$slot.' '.$key);
        }
    }
}
$state=['version'=>1,'rooms'=>[],'users'=>[]];
$config=['max_rooms'=>2,'lease_seconds'=>20,'poll_ms'=>1000]; $now=10000;
$a=atlas_api($state,['action'=>'connect','token'=>str_repeat('a',48),'nonce'=>str_repeat('a',32),'name'=>'A','protocol'=>1],$config,$now)['session'];
$b=atlas_api($state,['action'=>'connect','token'=>str_repeat('b',48),'nonce'=>str_repeat('b',32),'name'=>'B','protocol'=>1],$config,$now)['session'];
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
echo "PASS: $checks PHP checks\n";
