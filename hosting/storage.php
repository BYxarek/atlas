<?php
declare(strict_types=1);
// Offline operator tool: never expose backups or restore actions over HTTP.
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
require __DIR__.'/service.php';
try {
    if ($argc!==4 || !in_array($argv[1],['backup','restore'],true)) throw new RuntimeException('Usage: php storage.php backup|restore DATA_DIRECTORY SNAPSHOT_FILE');
    $base=realpath($argv[2]);
    if ($base===false || !is_dir($base)) throw new RuntimeException('Data directory does not exist');
    $lock=fopen($base.'/lock.php','c+');
    if (!$lock || !flock($lock,LOCK_EX)) throw new RuntimeException('Cannot lock storage');
    try {
        $source=$argv[1]==='backup'?$base.'/state.php':$argv[3];
        $raw=file_get_contents($source);
        if ($raw===false || !str_starts_with($raw,ATLAS_GUARD)) throw new RuntimeException('Invalid snapshot guard');
        $state=json_decode(substr($raw,strlen(ATLAS_GUARD)),true,128,JSON_THROW_ON_ERROR);
        if (($state['version']??0)!==1 || !is_array($state['rooms']??null) || !is_array($state['users']??null)) throw new RuntimeException('Unsupported snapshot');
        if ($argv[1]==='backup') {
            $target=fopen($argv[3],'x');
            if (!$target) throw new RuntimeException('Cannot create snapshot; use a new filename');
            try { if (fwrite($target,$raw)!==strlen($raw) || !fflush($target)) throw new RuntimeException('Cannot write snapshot'); }
            finally { fclose($target); }
        } else {
            // Keep the previous state available for rollback and reject invalid input before touching it.
            $path=$base.'/state.php';
            if (realpath($source)===realpath($path)) throw new RuntimeException('Snapshot must be a separate file');
            if (is_file($path) && !copy($path,$base.'/before-restore.php')) throw new RuntimeException('Cannot preserve previous state');
            if (file_put_contents($path.'.tmp.php',$raw)!==strlen($raw) || !rename($path.'.tmp.php',$path)) throw new RuntimeException('Cannot restore snapshot');
        }
        echo "OK: ".$argv[1]."\n";
    } finally { flock($lock,LOCK_UN); fclose($lock); }
} catch (Throwable $error) { fwrite(STDERR,$error->getMessage()."\n"); exit(1); }
