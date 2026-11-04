<?php
declare(strict_types=1);
ini_set('display_errors','0');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
require __DIR__.'/service.php';
try {
    if ($_SERVER['REQUEST_METHOD']!=='POST') { http_response_code(405); throw new DomainException('Use POST'); }
    if ((int)($_SERVER['CONTENT_LENGTH']??0)>8192) { http_response_code(413); throw new DomainException('Request too large'); }
    $raw=file_get_contents('php://input',false,null,0,8193);
    if (strlen($raw)>8192) { http_response_code(413); throw new DomainException('Request too large'); }
    $request=json_decode($raw,true,16,JSON_THROW_ON_ERROR);
    if (!is_array($request) || array_is_list($request)) throw new DomainException('Invalid JSON object');
    $config=atlas_config();
    $reply=atlas_transaction($config,fn(&$state)=>atlas_api($state,$request,$config,time()));
    echo json_encode($reply,JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR);
} catch (UnexpectedValueException $error) {
    http_response_code(401); echo json_encode(['ok'=>false,'error'=>$error->getMessage()]);
} catch (DomainException|JsonException $error) {
    if (http_response_code()===200) http_response_code(400);
    echo json_encode(['ok'=>false,'error'=>$error instanceof JsonException?'Invalid JSON':$error->getMessage()]);
} catch (Throwable $error) {
    error_log('ATLAS PHP: '.$error->getMessage()); http_response_code(503);
    echo json_encode(['ok'=>false,'error'=>'Хранилище сервера недоступно. Обратитесь к владельцу.']);
}
