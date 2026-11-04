<?php
declare(strict_types=1);
ini_set('display_errors','0');
require __DIR__.'/service.php';
try {
    $config=atlas_config();
    if (PHP_SAPI!=='cli') {
        $key=$_SERVER['HTTP_AUTHORIZATION']??($_GET['key']??'');
        $key=preg_replace('/^Bearer /','',$key);
        if (strlen($config['cron_key'])<32 || !hash_equals($config['cron_key'],$key)) { http_response_code(403); exit('Forbidden'); }
        header('Cache-Control: no-store');
    }
    $result=atlas_transaction($config,function(&$state)use($config){
        $sim=new AtlasWorld();
        foreach ($state['rooms'] as &$room) atlas_advance($room,time(),$config,$sim);
        return ['ok'=>true,'rooms'=>count($state['rooms'])];
    });
    echo json_encode($result)."\n";
} catch (Throwable $error) { error_log('ATLAS cron: '.$error->getMessage()); http_response_code(503); echo 'Cron failed'; if(PHP_SAPI==='cli')exit(1); }
