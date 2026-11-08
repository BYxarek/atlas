<?php
declare(strict_types=1);
ini_set('display_errors','0');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
require __DIR__.'/mod_catalog.php';
try {
    $hash=$_GET['hash']??''; $position=$_GET['offset']??'';
    if (($_SERVER['REQUEST_METHOD']??'')!=='GET' || !atlas_mod_hash($hash) || !is_string($position) || !preg_match('/^[0-9]{1,9}$/D',$position) || (int)$position%65536!==0) throw new DomainException('Invalid mod chunk request');
    foreach (atlas_mod_catalog() as $mod) if ($mod['sha256']===$hash && (int)$position<$mod['size']) {
        $file=fopen($mod['path'],'rb');
        if (!$file || fseek($file,(int)$position)!==0) throw new RuntimeException('Cannot read mod');
        $bytes=fread($file,65536); fclose($file);
        echo json_encode(['hash'=>$hash,'offset'=>(int)$position,'data'=>base64_encode($bytes)],JSON_THROW_ON_ERROR);
        exit;
    }
    http_response_code(404); echo '{"error":"Mod not found"}';
} catch (DomainException $error) { http_response_code(400); echo '{"error":"Invalid request"}'; }
catch (Throwable $error) { error_log('ATLAS mods: '.$error->getMessage()); http_response_code(503); echo '{"error":"Mods unavailable"}'; }
