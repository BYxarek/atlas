<?php
declare(strict_types=1);

function mr_number(mixed $v,float $low=0,float $high=1000000,bool $integer=true): bool {
    return (is_int($v)||is_float($v)) && is_finite((float)$v) && $v>=$low && $v<=$high && (!$integer || $v==floor($v));
}
function mr_text(mixed $v,int $limit=1024): bool { return is_string($v) && preg_match_all('/./us',$v)<=$limit; }
function mr_keys(mixed $v,array $allowed): bool { return is_array($v) && (!$v || !array_is_list($v)) && !array_diff(array_keys($v),$allowed); }
function mr_ids(mixed $v,array $allowed): bool {
    if (!is_array($v)||!array_is_list($v)||count($v)>64||count(array_unique($v,SORT_REGULAR))!==count($v)) return false;
    foreach($v as $id) if(!is_string($id)||!in_array($id,$allowed,true)) return false;
    return true;
}
function mr_army(mixed $v,int $count,int $low=0): bool { return is_array($v) && array_is_list($v) && count($v)===$count && !array_filter($v,fn($n)=>!mr_number($n,$low,100000000)); }
function mr_numbers(mixed $v,int $depth=0): mixed {
    if ($depth>32) return null;
    if (is_float($v) && is_finite($v) && $v==floor($v) && abs($v)<=1e12) return (int)$v;
    if (is_array($v)) foreach ($v as &$item) $item=mr_numbers($item,$depth+1);
    return $v;
}
function mr_defaults(): array { return ['units'=>[],'buildings'=>[],'technologies'=>[],'scenario'=>[],'victory'=>[],'events'=>[],'translations'=>[],'theme'=>[],'panels'=>[],'assets'=>[],'ai'=>[]]; }
function atlas_mod_compose(array $mods,array $base): array {
    $balance=$base; $content=mr_defaults(); $sources=[]; $conflicts=[];
    foreach ($mods as $mod) {
        $changes=$mod['changes']??[];
        if (!mr_keys($changes,array_keys($base))) throw new RuntimeException('Invalid changes or unknown balance key');
        if (isset($mod['network_balance'])) {
            if (!is_array($mod['network_balance'])) throw new RuntimeException('Invalid network_balance');
            $changes=array_replace($mod['network_balance'],$changes);
        }
        foreach ($changes as $key=>$value) {
            if (!array_key_exists($key,$base)) throw new RuntimeException('Unknown balance key: '.$key);
            if (isset($sources[$key]) && $balance[$key]!=$value) $conflicts[]=['field'=>$key,'previous'=>$sources[$key],'winner'=>$mod['id']];
            $balance[$key]=$value; $sources[$key]=$mod['id'];
        }
        $extra=$mod['content']??[];
        if (!mr_keys($extra,[...array_keys(mr_defaults()),'map'])) throw new RuntimeException('Unknown content field');
        foreach ($extra as $key=>$value) {
            if (in_array($key,['units','buildings','technologies','events','panels'],true)) {
                if (!is_array($value)||!array_is_list($value)) throw new RuntimeException('Expected content array');
                $content[$key]=array_merge($content[$key],$value);
            } elseif (in_array($key,['translations','theme','assets'],true)) {
                if (!is_array($value)||($value&&array_is_list($value))) throw new RuntimeException('Expected content object');
                if ($key==='translations') {
                    foreach ($value as $locale=>$catalog) {
                        if (!is_array($catalog)||($catalog&&array_is_list($catalog))) throw new RuntimeException('Expected translation catalog');
                        $content[$key][$locale]=array_replace($content[$key][$locale]??[],$catalog);
                    }
                } else $content[$key]=array_replace($content[$key],$value);
            } else $content[$key]=$value;
        }
    }
    mr_validate($content,$balance,$base);
    foreach ($content['units'] as $unit) foreach (['unit_cost'=>'cost','unit_weight'=>'weight','recruit_units'=>'recruit','start_units'=>'start'] as $key=>$field) $balance[$key][]=$unit[$field]??0;
    return ['error'=>'','balance'=>$balance,'content'=>$content,'sources'=>$sources,'conflicts'=>$conflicts];
}
function mr_validate(array $c,array $b,array $base): void {
    if (!atlas_mod_balance_valid($b,$base)) throw new RuntimeException('Invalid composed balance');
    foreach (['units'=>13,'buildings'=>32,'technologies'=>32,'events'=>128,'panels'=>16] as $key=>$limit) if (count($c[$key])>$limit) throw new RuntimeException('Content limit exceeded');
    $unitIds=['infantry','aircraft','navy']; $techIds=[]; $buildingIds=[];
    foreach ($c['technologies'] as $t) {
        if (!mr_keys($t,['id','name','cost','requires','unit','bonus','income']) || !atlas_mod_id($t['id']??null) || in_array($t['id'],$techIds,true) || !mr_text($t['name']??null,160) || !mr_number($t['cost']??null,1)) throw new RuntimeException('Invalid technology');
        $techIds[]=$t['id'];
    }
    foreach ($c['units'] as $u) {
        if (!mr_keys($u,['id','name','cost','weight','recruit','start','requires']) || !atlas_mod_id($u['id']??null) || in_array($u['id'],$unitIds,true) || !mr_text($u['name']??null,160)) throw new RuntimeException('Invalid unit');
        foreach (['cost','weight','recruit'] as $key) if (!mr_number($u[$key]??null,1)) throw new RuntimeException('Invalid unit value');
        if (!mr_number($u['start']??0)||!mr_ids($u['requires']??[],$techIds)) throw new RuntimeException('Invalid unit requirements');
        $unitIds[]=$u['id'];
    }
    foreach ($c['buildings'] as $item) {
        if (!mr_keys($item,['id','name','cost','income','requires'])||!atlas_mod_id($item['id']??null)||in_array($item['id'],$buildingIds,true)||!mr_text($item['name']??null,160)||!mr_number($item['cost']??null,1)||!mr_number($item['income']??null)||!mr_ids($item['requires']??[],$techIds)) throw new RuntimeException('Invalid building');
        $buildingIds[]=$item['id'];
    }
    $visited=[];
    foreach ($c['technologies'] as $t) {
        if (!mr_ids($t['requires']??[],$visited)||!in_array($t['unit']??'infantry',$unitIds,true)||!mr_number($t['bonus']??0,0,1,false)||!mr_number($t['income']??0)) throw new RuntimeException('Invalid technology dependencies or bonus');
        $visited[]=$t['id'];
    }
    $ai=$c['ai'];
    if (!mr_keys($ai,['priorities','attack_ratio','targets','retreat_ratio'])||!mr_number($ai['attack_ratio']??1,0,2,false)||!mr_number($ai['retreat_ratio']??0,0,2,false)||!in_array($ai['targets']??'weakest',['weakest','income','nearest'],true)||!is_array($ai['priorities']??[])||count($ai['priorities']??[])>32) throw new RuntimeException('content.ai: invalid rules');
    foreach ($ai['priorities']??[] as $i=>$p) {
        if (!mr_keys($p,['action','id','reserve','max_level'])||!in_array($p['action']??null,['research','construct','recruit','upgrade','business'],true)||!mr_number($p['reserve']??0,0,100000000)||!mr_number($p['max_level']??10,1)) throw new RuntimeException("content.ai.priorities[$i]: invalid rule");
        $available=$p['action']==='research'?$techIds:($p['action']==='construct'?$buildingIds:$unitIds);
        if ($p['action']!=='business'&&!in_array($p['id']??null,$available,true)) throw new RuntimeException("content.ai.priorities[$i].id: unknown reference");
    }
    $atlas=$c['map']??json_decode(file_get_contents(__DIR__.'/data.json'),true,64,JSON_THROW_ON_ERROR)['atlas'];
    if (!is_array($atlas)||!array_is_list($atlas)||count($atlas)<3||count($atlas)>512) throw new RuntimeException('Invalid map size');
    $count=count($atlas);
    if (isset($c['map'])) {
        $point=fn($p)=>is_array($p)&&array_is_list($p)&&count($p)===2&&mr_number($p[0],-180,180,false)&&mr_number($p[1],-90,90,false);
        foreach ($atlas as $i=>$country) {
            if (!is_array($country)||($country['id']??null)!=$i||!mr_text($country['name']??null,160)||!mr_text($country['english']??null,160)||!mr_text($country['continent']??null,80)||!$point($country['center']??null)) throw new RuntimeException('Invalid map country');
            if (!is_array($country['rings']??null)||!$country['rings']||count($country['rings'])>64) throw new RuntimeException('Invalid map geometry');
            $points=0;
            foreach ($country['rings'] as $ring) {
                if (!is_array($ring)||!array_is_list($ring)||count($ring)<3||count($ring)>2000||array_filter($ring,fn($p)=>!$point($p))) throw new RuntimeException('Invalid map ring');
                $points+=count($ring);
            }
            if ($points>10000||!mr_number($country['sovereign']??null,0,$count-1)) throw new RuntimeException('Invalid map references');
            foreach (['neighbors','enclave_hosts','dependencies'] as $key) if (!is_array($country[$key]??null)||!array_is_list($country[$key])||count($country[$key])>$count||in_array($i,$country[$key],true)||array_filter($country[$key],fn($id)=>!mr_number($id,0,$count-1))) throw new RuntimeException('Invalid map links');
        }
        foreach ($atlas as $i=>$country) foreach ($country['neighbors'] as $id) if (!in_array($i,$atlas[$id]['neighbors'],true)) throw new RuntimeException('Map borders must be reciprocal');
    }
    $s=$c['scenario']; $branches=count($unitIds);
    if (!mr_keys($s,['name','default_home','starts','armies','alliances'])||!mr_text($s['name']??'',160)||!mr_number($s['default_home']??0,0,$count-1)||!is_array($s['starts']??[])||count($s['starts']??[])>$count||!is_array($s['armies']??[])) throw new RuntimeException('Invalid scenario');
    $reserved=[];
    foreach ($s['starts']??[] as $key=>$start) {
        if (!preg_match('/^[0-9]+$/D',(string)$key)||!mr_number((int)$key,0,$count-1)||!mr_keys($start,['coins','units','levels','owned','researches'])||!mr_number($start['coins']??$b['start_coins'],0,100000000)) throw new RuntimeException('Invalid scenario start');
        foreach (['units','levels'] as $field) if (isset($start[$field])&&!mr_army($start[$field],$branches,$field==='levels'?1:0)) throw new RuntimeException('Invalid scenario army');
        if (!mr_ids($start['researches']??[],$techIds)) throw new RuntimeException('Invalid initial research');
        $owned=$start['owned']??[];
        if (!is_array($owned)||!array_is_list($owned)||count($owned)>$count||array_filter($owned,fn($id)=>!mr_number($id,0,$count-1))) throw new RuntimeException('Invalid initial territories');
        foreach (array_unique([(int)$key,...$owned]) as $id) {
            if (in_array($id,$reserved,true)||$atlas[$id]['enclave_hosts']) throw new RuntimeException('Scenario starts overlap or include hidden microstate');
            $reserved[]=$id;
        }
    }
    foreach ($s['armies']??[] as $key=>$army) if (!preg_match('/^[0-9]+$/D',(string)$key)||!mr_number((int)$key,0,$count-1)||!mr_army($army,$branches)) throw new RuntimeException('Invalid scenario garrison');
    if (!is_array($s['alliances']??[])||count($s['alliances']??[])>32) throw new RuntimeException('Invalid alliances');
    $allies=[];
    foreach ($s['alliances']??[] as $group) {
        if (!is_array($group)||!array_is_list($group)||count($group)<2||count($group)>$count) throw new RuntimeException('Invalid alliance');
        foreach ($group as $id) { if (!mr_number($id,0,$count-1)||in_array($id,$allies,true)) throw new RuntimeException('Alliance groups overlap'); $allies[]=$id; }
    }
    $goal=$c['victory'];
    if (!mr_keys($goal,['type','amount','countries','seconds'])) throw new RuntimeException('Invalid victory condition');
    if ($goal) {
        if (!in_array($goal['type']??null,['world','coins','countries','hold','time'],true)) throw new RuntimeException('Unknown victory type');
        if ($goal['type']==='coins'&&!mr_number($goal['amount']??null,1,100000000)) throw new RuntimeException('Invalid victory amount');
        if (in_array($goal['type'],['countries','hold'],true)&&(!is_array($goal['countries']??null)||!$goal['countries']||array_filter($goal['countries'],fn($id)=>!mr_number($id,0,$count-1)))) throw new RuntimeException('Invalid victory countries');
        if (in_array($goal['type'],['hold','time'],true)&&!mr_number($goal['seconds']??null,1)) throw new RuntimeException('Invalid victory time');
    }
    $eventIds=[]; $flagIds=[];
    foreach ($c['events'] as $e) {
        if (!mr_keys($e,['id','when','conditions','actions','once','cooldown'])||!atlas_mod_id($e['id']??null)||in_array($e['id'],$eventIds,true)||!in_array($e['when']??null,['start','tick','country_captured','research_completed','building_built','mission_completed'],true)||!is_bool($e['once']??true)||!mr_number($e['cooldown']??1,1)) throw new RuntimeException('Invalid event');
        $condition=$e['conditions']??[];
        if (!mr_keys($condition,['country_id','elapsed_min','coins_min','owns','researches','flags','chance'])||!mr_number($condition['country_id']??0,0,$count-1)||!mr_number($condition['elapsed_min']??0)||!mr_number($condition['coins_min']??0,0,100000000)||!mr_number($condition['chance']??100,0,100)) throw new RuntimeException('Invalid event conditions');
        if (!is_array($condition['owns']??[])||array_filter($condition['owns']??[],fn($id)=>!mr_number($id,0,$count-1))||!mr_ids($condition['researches']??[],$techIds)) throw new RuntimeException('Invalid event references');
        if (!is_array($condition['flags']??[])||count($condition['flags']??[])>32) throw new RuntimeException('Invalid flags');
        foreach ($condition['flags']??[] as $key=>$value) if (!atlas_mod_id($key)||(!is_bool($value)&&!mr_number($value,-1000000))) throw new RuntimeException('Invalid flag condition');
        if (!is_array($e['actions']??null)||!$e['actions']||count($e['actions'])>16) throw new RuntimeException('Invalid event actions');
        foreach ($e['actions'] as $a) {
            if (!mr_keys($a,['type','amount','unit','text','key','value','technology','country_id'])||!in_array($a['type']??null,['add_coins','add_units','show_message','set_flag','grant_research','capture_country','release_country','win','lose'],true)||!mr_number($a['amount']??0,-1000000)||!in_array($a['unit']??'infantry',$unitIds,true)||!mr_text($a['text']??'',400)) throw new RuntimeException('Invalid event action');
            if ($a['type']==='set_flag'&&(!atlas_mod_id($a['key']??null)||(!is_bool($a['value']??null)&&!mr_number($a['value']??null,-1000000)))) throw new RuntimeException('Invalid flag action');
            if ($a['type']==='set_flag') $flagIds[$a['key']]=true;
            if (count($flagIds)>128) throw new RuntimeException('Too many event flags');
            if ($a['type']==='grant_research'&&!in_array($a['technology']??null,$techIds,true)) throw new RuntimeException('Unknown research reward');
            if (in_array($a['type'],['capture_country','release_country'],true)&&!mr_number($a['country_id']??null,0,$count-1)) throw new RuntimeException('Invalid event country');
        }
        $eventIds[]=$e['id'];
    }
    if (!mr_keys($c['theme'],['ink','muted','accent','ocean','unknown'])) throw new RuntimeException('Unknown theme color');
    foreach ($c['theme'] as $color) if (!is_string($color)||!preg_match('/^#?(?:[a-fA-F0-9]{3}|[a-fA-F0-9]{4}|[a-fA-F0-9]{6}|[a-fA-F0-9]{8})$/D',$color)) throw new RuntimeException('Invalid theme color');
    if (!mr_keys($c['translations'],['ru','en'])) throw new RuntimeException('Invalid translation locale');
    foreach ($c['translations'] as $catalog) {
        if (!is_array($catalog)||count($catalog)>512) throw new RuntimeException('Invalid translation catalog');
        foreach ($catalog as $key=>$value) if (!mr_text($key)||!mr_text($value)) throw new RuntimeException('Invalid translation');
    }
    foreach ($c['panels'] as $panel) if (!mr_keys($panel,['id','title','text','action'])||!atlas_mod_id($panel['id']??null)||!mr_text($panel['title']??null,160)||!mr_text($panel['text']??'')||!in_array($panel['action']??'',['','army','economy','countries','notifications'],true)) throw new RuntimeException('Invalid UI panel');
    if (count(array_column($c['panels'],'id'))!==count(array_unique(array_column($c['panels'],'id')))) throw new RuntimeException('Duplicate UI panel');
    if (!is_array($c['assets'])||count($c['assets'])>64) throw new RuntimeException('Invalid media catalog');
    foreach ($c['assets'] as $key=>$value) if ((str_starts_with($key,'flag:')&&!mr_number((int)substr($key,5),0,$count-1))||!mr_media($key,$value)) throw new RuntimeException('Invalid media');
}
function mr_media(string $key,mixed $value): bool {
    if (!mr_keys($value,['mime','data'])||!in_array($value['mime']??null,['image/png','audio/wav'],true)||!is_string($value['data']??null)||strlen($value['data'])>262144) return false;
    $bytes=base64_decode($value['data'],true);
    if ($bytes===false||!$bytes||strlen($bytes)>196608||base64_encode($bytes)!==$value['data']) return false;
    if (str_starts_with($key,'sound:')&&atlas_mod_id(substr($key,6))) return $value['mime']==='audio/wav'&&strlen($bytes)>=44&&substr($bytes,0,4)==='RIFF'&&substr($bytes,8,4)==='WAVE';
    if (!preg_match('/^flag:[0-9]+$/D',$key)||$value['mime']!=='image/png'||strlen($bytes)<24||substr($bytes,0,8)!=="\x89PNG\r\n\x1a\n") return false;
    $width=unpack('N',substr($bytes,16,4))[1]; $height=unpack('N',substr($bytes,20,4))[1];
    return $width>0&&$height>0&&$width<=1024&&$height<=1024;
}
function atlas_mod_composed(): array {
    static $result;
    return $result??=atlas_mod_compose(atlas_mod_catalog(),json_decode(file_get_contents(__DIR__.'/balance.json'),true,32,JSON_THROW_ON_ERROR));
}
function atlas_mod_world(): array {
    static $result;
    if ($result!==null) return $result;
    $result=json_decode(file_get_contents(__DIR__.'/data.json'),true,64,JSON_THROW_ON_ERROR);
    $compiled=atlas_mod_composed(); $c=$compiled['content']; $n=count($compiled['balance']['start_units']);
    if (isset($c['map'])) { $result['atlas']=$c['map']; $result['countries']=array_fill(0,count($c['map']),['owned'=>false,'businesses'=>[1],'units'=>[18,3,0]]); }
    foreach ($result['countries'] as $id=>&$country) $country['units']=$c['scenario']['armies'][(string)$id]??array_pad($country['units'],$n,0);
    unset($country);
    return $result;
}
