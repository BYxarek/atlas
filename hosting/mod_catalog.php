<?php
declare(strict_types=1);
require_once __DIR__.'/mod_rules.php';

function atlas_mod_id(mixed $id): bool {
    return is_string($id) && preg_match('/^[a-z0-9_-]{1,64}$/D',$id)===1;
}
function atlas_mod_hash(mixed $hash): bool {
    return is_string($hash) && preg_match('/^[a-f0-9]{64}$/D',$hash)===1;
}
function atlas_mod_balance_valid(mixed $value,array $base): bool {
    if (!is_array($value) || count($value)!==count($base) || ($value['version']??null)!=$base['version']) return false;
    foreach ($base as $key=>$template) {
        if (!array_key_exists($key,$value)) return false;
        $values=is_array($template)?$value[$key]:[$value[$key]];
        if (!is_array($values) || !array_is_list($values) || count($values)!==(is_array($template)?3:1)) return false;
        foreach ($values as $number) {
            if ((!is_int($number)&&!is_float($number)) || !is_finite((float)$number) || $number<0 || $number>1000000) return false;
            if (!in_array($key,['technology_bonus','naval_multiplier','attack_loss','attack_loss_min','attack_loss_max','defender_retreat_loss','defender_hold_loss'],true) && (float)$number!==floor((float)$number)) return false;
            if (in_array($key,['nuclear_threshold','spy_seconds','attack_seconds','nuke_seconds','bot_seconds','naval_ships','bot_max_level','unit_weight'],true) && $number<1) return false;
            if ((str_ends_with($key,'chance') || $key==='bot_economy_bonus') && $number>100) return false;
            if (in_array($key,['technology_bonus','naval_multiplier','attack_loss','attack_loss_min','attack_loss_max','defender_retreat_loss','defender_hold_loss'],true) && $number>1) return false;
        }
    }
    return $value['attack_loss_min']<=$value['attack_loss_max'];
}
function atlas_mod_read(string $path): array {
    $size=filesize($path);
    if ($size<16 || $size>67108864) throw new RuntimeException('Invalid .atlasmod size');
    $file=fopen($path,'rb');
    if (!$file) throw new RuntimeException('Cannot open .atlasmod');
    try {
        if (fread($file,8)!=='ATLASMOD') throw new RuntimeException('Invalid .atlasmod header');
        $length=unpack('V',fread($file,4))[1];
        if ($length<2 || $length>4194304 || $length+16>$size) throw new RuntimeException('Invalid .atlasmod manifest size');
        $data=mr_numbers(json_decode(fread($file,$length),true,32,JSON_THROW_ON_ERROR));
        if (!is_array($data) || !atlas_mod_id($data['id']??null) || (!is_int($data['api']??null)&&!is_float($data['api']??null)) || !in_array($data['api'],[1,2],true) || !atlas_mod_hash($data['pck_sha256']??null)) throw new RuntimeException('Invalid mod manifest');
        foreach (['name','version','game_version'] as $key) if (!is_string($data[$key]??null) || $data[$key]==='' || mb_strlen_atlas($data[$key])>160) throw new RuntimeException('Invalid mod '.$key);
        if ($data['game_version']!=='0.3.0') throw new RuntimeException('Incompatible game version');
        if (!is_string($data['description']??'') || mb_strlen_atlas($data['description']??'')>4096) throw new RuntimeException('Invalid description');
        foreach (['requires','conflicts'] as $key) {
            $data[$key]??=[];
            if (!is_array($data[$key]) || !array_is_list($data[$key]) || count($data[$key])>32) throw new RuntimeException('Invalid mod dependencies');
            foreach ($data[$key] as $id) if (!atlas_mod_id($id) || $id===$data['id']) throw new RuntimeException('Invalid dependency');
        }
        $base=json_decode(file_get_contents(__DIR__.'/balance.json'),true,32,JSON_THROW_ON_ERROR);
        if ($data['api']===1 && !atlas_mod_balance_valid($data['network_balance']??null,$base)) throw new RuntimeException('Mod has no compatible shared network rules: '.$data['id']);
        $offset=ftell($file);
        if (fread($file,4)!=='GDPC') throw new RuntimeException('Invalid embedded PCK');
        fseek($file,$offset);
        $hash=hash_init('sha256'); hash_update_stream($hash,$file);
        if (!hash_equals($data['pck_sha256'],hash_final($hash))) throw new RuntimeException('PCK checksum mismatch');
        $data['sha256']=hash_file('sha256',$path); $data['size']=$size; $data['path']=$path;
        return $data;
    } finally { fclose($file); }
}
function mb_strlen_atlas(string $value): int { return preg_match_all('/./us',$value); }
function atlas_mod_catalog(?string $folder=null): array {
    static $cache=[];
    $folder??=__DIR__.'/network_mods';
    if (isset($cache[$folder])) return $cache[$folder];
    $paths=array_values(array_filter(glob($folder.'/*')?:[],fn($path)=>is_file($path) && strtolower(pathinfo($path,PATHINFO_EXTENSION))==='atlasmod')); sort($paths,SORT_STRING);
    if (count($paths)>32) throw new RuntimeException('Too many network mods');
    $result=[]; $ids=[]; $total=0;
    foreach ($paths as $path) {
        $mod=atlas_mod_read($path);
        if (in_array($mod['id'],$ids,true)) throw new RuntimeException('Duplicate network mod');
        foreach ($mod['requires'] as $id) if (!in_array($id,$ids,true)) throw new RuntimeException('Wrong dependency order');
        $ids[]=$mod['id']; $total+=$mod['size']; $result[]=$mod;
    }
    foreach ($result as $mod) foreach ($mod['conflicts'] as $id) if (in_array($id,$ids,true)) throw new RuntimeException('Conflicting network mods');
    if ($total>134217728) throw new RuntimeException('Network mods exceed total size limit');
    atlas_mod_compose($result,json_decode(file_get_contents(__DIR__.'/balance.json'),true,32,JSON_THROW_ON_ERROR));
    return $cache[$folder]=$result;
}
function atlas_mod_profile(): array {
    $result=[];
    foreach (atlas_mod_catalog() as $mod) $result[]=array_intersect_key($mod,array_flip(['api','id','name','version','game_version','sha256','size','pck_sha256','requires','conflicts']));
    return $result;
}
function atlas_mod_fingerprint(): string {
    $identity=array_map(fn($mod)=>[$mod['id'],$mod['version'],$mod['sha256']],atlas_mod_catalog());
    return $identity?hash('sha256',json_encode($identity,JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE|JSON_THROW_ON_ERROR)):'';
}
function atlas_mod_hashes(): array { return array_column(atlas_mod_catalog(),'sha256'); }
