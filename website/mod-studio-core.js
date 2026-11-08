/* Shared by the editor and its dependency-free Node tests. */
(function(root){
 'use strict';
 const clone=x=>JSON.parse(JSON.stringify(x));
 const object=x=>x!==null&&typeof x==='object'&&!Array.isArray(x);
 const id=x=>typeof x==='string'&&/^[a-z0-9_-]{1,64}$/.test(x);
 const number=(x,min=0,max=1000000,integer=true)=>typeof x==='number'&&Number.isFinite(x)&&x>=min&&x<=max&&(!integer||Number.isInteger(x));
 const branches=d=>['infantry','aircraft','navy',...(d.content?.units||[]).map(x=>x.id)];
 const triggers=['start','tick','country_captured','research_completed','building_built','mission_completed'];
 const actions=['add_coins','add_units','show_message','set_flag','grant_research','capture_country','release_country','win','lose'];
 const fields={units:{id:'id',name:'text',cost:'positive',weight:'positive',recruit:'positive',start:'number',requires:'techs'},buildings:{id:'id',name:'text',cost:'positive',income:'number',requires:'techs'},technologies:{id:'id',name:'text',cost:'positive',requires:'techs',unit:'unit',bonus:'fraction',income:'number'},panels:{id:'id',title:'text',text:'long',action:'panel'}};
 function intersects(a,b,c,d){
   const cross=(p,q,r)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
   const between=(p,q,r)=>Math.min(p[0],q[0])<=r[0]&&r[0]<=Math.max(p[0],q[0])&&Math.min(p[1],q[1])<=r[1]&&r[1]<=Math.max(p[1],q[1]);
   const u=cross(a,b,c),v=cross(a,b,d),w=cross(c,d,a),z=cross(c,d,b);
   return (u*v<0&&w*z<0)||(u===0&&between(a,b,c))||(v===0&&between(a,b,d))||(w===0&&between(c,d,a))||(z===0&&between(c,d,b));
 }
 function ringIssues(r){
   if(!Array.isArray(r)||r.length<3||r.length>2000)return ['Expected 3–2000 vertices'];
   if(r.some(p=>!Array.isArray(p)||p.length!==2||!number(p[0],-180,180,false)||!number(p[1],-90,90,false)))return ['Invalid longitude/latitude'];
   const points=r.length>3&&r[0][0]===r.at(-1)[0]&&r[0][1]===r.at(-1)[1]?r.slice(0,-1):r;
   let area=0;
   for(let i=0;i<points.length;i++){const a=points[i],b=points[(i+1)%points.length];area+=a[0]*b[1]-b[0]*a[1];
     for(let j=i+2;j<points.length;j++){if(i===0&&j===points.length-1)continue;if(intersects(a,b,points[j],points[(j+1)%points.length]))return ['Self-intersection / repeated vertex'];}}
   return Math.abs(area)<1e-10?['Polygon has zero area']:[];
 }
 function touching(a,b){
   let checks=0;
   for(const r of a.rings||[])for(const s of b.rings||[]){
     const bounds=p=>[Math.min(...p.map(x=>x[0])),Math.min(...p.map(x=>x[1])),Math.max(...p.map(x=>x[0])),Math.max(...p.map(x=>x[1]))],x=bounds(r),y=bounds(s);
     if(x[2]<y[0]||y[2]<x[0]||x[3]<y[1]||y[3]<x[1])continue;
     const points=new Set(r.map(p=>p.join(',')));if(s.some(p=>points.has(p.join(','))))return true;
     for(let i=0;i<r.length;i++)for(let j=0;j<s.length;j++){if(++checks>50000)return null;if(intersects(r[i],r[(i+1)%r.length],s[j],s[(j+1)%s.length]))return true;}
   }return false;
 }
 function diagnose(d,base,atlas){
   const issues=[];const add=(path,message,severity='error')=>issues.push({path,message,severity});
   const keys=(v,allowed,path)=>{if(!object(v)){add(path,'Expected an object');return false;}for(const k of Object.keys(v))if(!allowed.includes(k))add(path+'.'+k,'Unknown field');return true;};
   const num=(v,path,min=0,max=1000000,int=true)=>{if(!number(v,min,max,int))add(path,`Expected ${int?'integer':'number'} ${min}…${max}`);};
   const refs=(v,available,path)=>{if(!Array.isArray(v)||v.length>512||new Set(v).size!==v.length)add(path,'Expected unique reference list');else v.forEach((x,i)=>{if(!available.includes(x))add(`${path}[${i}]`,'Unknown reference: '+x);});};
   if(!object(d)){add('$','Expected manifest object');return issues;}
   if(d.api!==2)add('api','Editor supports API 2; native payloads are preserved but never executed');
   if(!id(d.id))add('id','Use 1–64 lowercase ASCII letters, digits, _ or -');
   for(const k of ['name','version','game_version'])if(typeof d[k]!=='string'||!d[k].length||d[k].length>160)add(k,'Expected nonempty text, max 160 characters');
   if(d.game_version!=='0.3.0')add('game_version','Expected game version 0.3.0');
   for(const k of ['requires','conflicts']){const v=d[k]||[];if(!Array.isArray(v)||v.length>32||v.some(x=>!id(x)||x===d.id))add(k,'Invalid mod references');}
   const balance={...base,...(d.network_balance||{}),...(d.changes||{})};
   if(keys(d.changes||{},Object.keys(base),'changes'))for(const [k,v] of Object.entries(d.changes||{})){
     if(!(k in base))continue;const fractions=['technology_bonus','naval_multiplier','attack_loss','attack_loss_min','attack_loss_max','defender_retreat_loss','defender_hold_loss'];
     const positive=['nuclear_threshold','spy_seconds','attack_seconds','nuke_seconds','bot_seconds','naval_ships','bot_max_level','unit_weight'];
     const max=fractions.includes(k)?1:k.endsWith('chance')||k==='bot_economy_bonus'?100:1000000;
     if(Array.isArray(base[k])){if(!Array.isArray(v)||v.length!==3)add('changes.'+k,'Expected 3 values');else v.forEach((n,i)=>num(n,`changes.${k}[${i}]`,positive.includes(k)?1:0,max));}
     else num(v,'changes.'+k,positive.includes(k)?1:0,max,!fractions.includes(k));
   }
   if(balance.version!==1)add('changes.version','Schema version must remain 1');
   if(balance.attack_loss_min>balance.attack_loss_max)add('changes.attack_loss_min','Must not exceed attack_loss_max');
   const c=d.content||{};
   if(!keys(c,['units','buildings','technologies','events','panels','scenario','victory','map','translations','theme','assets','ai'],'content'))return issues;
   for(const [kind,max] of Object.entries({units:13,buildings:32,technologies:32,events:128,panels:16})){
     const list=c[kind]||[];if(!Array.isArray(list)||list.length>max){add('content.'+kind,'Expected array, maximum '+max);continue;}
     const seen=new Set(kind==='units'?['infantry','aircraft','navy']:[]);
     list.forEach((v,i)=>{const path=`content.${kind}[${i}]`;if(!object(v)){add(path,'Expected an object');return;}if(!id(v.id)||seen.has(v.id))add(path+'.id','Invalid or duplicate ID');seen.add(v.id);});
   }
   if(issues.some(x=>x.path.match(/^content\.(units|buildings|technologies|events|panels)/)))return issues;
   const units=branches(d),techs=(c.technologies||[]).map(x=>x.id),buildings=(c.buildings||[]).map(x=>x.id);
   for(const kind of Object.keys(fields))for(const [i,v] of (c[kind]||[]).entries()){
     const path=`content.${kind}[${i}]`;
     keys(v,Object.keys(fields[kind]),path);
     for(const [k,type] of Object.entries(fields[kind])){
       const value=v[k];const p=path+'.'+k;
       if(['cost','weight','recruit'].includes(k)&&value===undefined){add(p,'Required field');continue;}if(value===undefined)continue;
       if(type==='positive'||type==='number'||type==='fraction')num(value,p,type==='positive'?1:0,type==='fraction'?1:1000000,type!=='fraction');
       else if(type==='techs')refs(value,kind==='technologies'?techs.slice(0,i):techs,p);
       else if(type==='unit'&&!units.includes(value))add(p,'Unknown troop branch');
       else if(type==='panel'&&!['','army','economy','countries','notifications'].includes(value))add(p,'Unknown panel action');
       else if(['text','long'].includes(type)&&(typeof value!=='string'||value.length>(type==='long'?1024:160)))add(p,'Invalid text length');
     }
     if(kind!=='panels'&&typeof v.name!=='string')add(path+'.name','Name is required');
     if(kind==='panels'&&typeof v.title!=='string')add(path+'.title','Title is required');
   }
   const map=c.map||atlas;const countries=Array.isArray(map)?map.map((_,i)=>i):[];
   if(c.map){if(!Array.isArray(map)||map.length<3||map.length>512)add('content.map','Expected 3–512 countries');else map.forEach((country,i)=>{
     const path=`content.map[${i}]`;if(!object(country)){add(path,'Expected country');return;}
     if(country.id!==i)add(path+'.id','Country IDs must be contiguous');
     for(const k of ['name','english','continent'])if(typeof country[k]!=='string'||country[k].length>160)add(path+'.'+k,'Expected country text');
     if(!Array.isArray(country.center)||country.center.length!==2||!number(country.center[0],-180,180,false)||!number(country.center[1],-90,90,false))add(path+'.center','Expected longitude/latitude');
     for(const k of ['neighbors','dependencies','enclave_hosts'])refs(country[k]||[],countries.filter(x=>x!==i),path+'.'+k);
     if(!countries.includes(country.sovereign))add(path+'.sovereign','Unknown sovereign');
     for(const n of country.neighbors||[])if(countries.includes(n)){
       if(!map[n]?.neighbors?.includes(i))add(path+'.neighbors','Border with '+n+' is not mutual');
       if(n>i&&Array.isArray(country.rings)&&Array.isArray(map[n]?.rings)){const shared=touching(country,map[n]);if(shared===false)add(path+'.neighbors','Declared neighbor '+n+' has a geometric gap','warning');if(shared===null)add(path+'.neighbors','Detailed shared-border check reached its work limit; inspect '+n+' manually','warning');}
     }
     if(!Array.isArray(country.rings)||!country.rings.length||country.rings.length>64)add(path+'.rings','Expected 1–64 polygons');
     else {country.rings.forEach((r,j)=>ringIssues(r).forEach(message=>add(`${path}.rings[${j}]`,message)));if(country.rings.reduce((n,r)=>n+r.length,0)>10000)add(path+'.rings','Maximum 10000 vertices');}
     if(!country.neighbors?.length)add(path+'.neighbors','No land neighbors; check naval access','warning');
   });}
   const army=(v,path,min=0)=>{if(!Array.isArray(v)||v.length!==units.length)add(path,'Expected '+units.length+' troop values');else v.forEach((n,i)=>num(n,path+'['+i+']',min,100000000));};
   const scenario=c.scenario||{};keys(scenario,['name','default_home','starts','armies','alliances'],'content.scenario');
   if(scenario.default_home!==undefined&&!countries.includes(scenario.default_home))add('content.scenario.default_home','Unknown country');
   const claimed=new Set();
   for(const [country,v] of Object.entries(scenario.starts||{})){
     const path='content.scenario.starts.'+country;if(!countries.includes(Number(country)))add(path,'Unknown start country');
     if(!keys(v,['coins','units','levels','owned','researches'],path))continue;
     if(v.coins!==undefined)num(v.coins,path+'.coins',0,100000000);
     if(v.units)army(v.units,path+'.units');if(v.levels)army(v.levels,path+'.levels',1);
     refs(v.owned||[],countries,path+'.owned');refs(v.researches||[],techs,path+'.researches');
     for(const id of new Set([Number(country),...(v.owned||[])])){if(claimed.has(id))add(path+'.owned','Starting territories overlap at '+id);claimed.add(id);if(map[id]?.enclave_hosts?.length)add(path+'.owned','Hidden microstate '+id+' cannot be a start');}
   }
   for(const [id,v] of Object.entries(scenario.armies||{})){if(!countries.includes(Number(id)))add('content.scenario.armies.'+id,'Unknown country');army(v,'content.scenario.armies.'+id);}
   const allies=new Set();for(const [i,group] of (scenario.alliances||[]).entries()){refs(group,countries,`content.scenario.alliances[${i}]`);if(group.length<2)add(`content.scenario.alliances[${i}]`,'At least two countries');for(const id of group){if(allies.has(id))add('content.scenario.alliances','Groups overlap');allies.add(id);}}
   const goal=c.victory||{};keys(goal,['type','amount','countries','seconds'],'content.victory');
   if(Object.keys(goal).length&&!['world','coins','countries','hold','time'].includes(goal.type))add('content.victory.type','Unknown goal');
   if(goal.type==='coins')num(goal.amount,'content.victory.amount',1,100000000);
   if(['countries','hold'].includes(goal.type)){refs(goal.countries||[],countries,'content.victory.countries');if(!goal.countries?.length)add('content.victory.countries','Select at least one country');}
   if(['hold','time'].includes(goal.type))num(goal.seconds,'content.victory.seconds',1);
   const flags=new Set();let budget=0;
   for(const [i,e] of (c.events||[]).entries()){
     const p=`content.events[${i}] (${e.id})`;keys(e,['id','when','conditions','actions','once','cooldown'],p);
     if(!triggers.includes(e.when))add(p+'.when','Unknown trigger');if(e.once!==undefined&&typeof e.once!=='boolean')add(p+'.once','Expected boolean');num(e.cooldown??1,p+'.cooldown',1);
     const cond=e.conditions||{};keys(cond,['country_id','elapsed_min','coins_min','owns','researches','flags','chance'],p+'.conditions');
     if(cond.country_id!==undefined&&!countries.includes(cond.country_id))add(p+'.conditions.country_id','Unknown country');
     for(const k of ['elapsed_min','coins_min','chance'])if(cond[k]!==undefined)num(cond[k],p+'.conditions.'+k,0,k==='chance'?100:k==='coins_min'?100000000:1000000);
     refs(cond.owns||[],countries,p+'.conditions.owns');refs(cond.researches||[],techs,p+'.conditions.researches');
     if(cond.chance===0)add(p+'.conditions.chance','Event can never fire','warning');
     if(!Array.isArray(e.actions)||!e.actions.length||e.actions.length>16){add(p+'.actions','Expected 1–16 actions');continue;}
     budget+=e.actions.length;
     for(const [j,a] of e.actions.entries()){
       const q=p+`.actions[${j}]`;if(!keys(a,['type','amount','unit','text','key','value','technology','country_id'],q))continue;
       if(!actions.includes(a.type))add(q+'.type','Unknown action');
       if(a.amount!==undefined)num(a.amount,q+'.amount',-1000000);
       if(a.type==='add_units'&&!units.includes(a.unit||'infantry'))add(q+'.unit','Unknown troop branch: '+a.unit);
       if(a.type==='show_message'&&(typeof a.text!=='string'||a.text.length>400))add(q+'.text','Expected text, max 400 characters');
       if(a.type==='set_flag'){if(!id(a.key)||!(typeof a.value==='boolean'||number(a.value,-1000000)))add(q+'.value','Flag needs a valid key and boolean/integer value');flags.add(a.key);}
       if(a.type==='grant_research'&&!techs.includes(a.technology))add(q+'.technology','Unknown research');
       if(['capture_country','release_country'].includes(a.type)&&!countries.includes(a.country_id))add(q+'.country_id','Unknown country');
     }
   }
   if(flags.size>128)add('content.events','Maximum 128 distinct flags');
   if(budget>64)add('content.events','Total actions exceed 64; events sharing a trigger may exhaust its budget','warning');
   const ai=c.ai||{};keys(ai,['priorities','attack_ratio','retreat_ratio','targets'],'content.ai');
   num(ai.attack_ratio??1,'content.ai.attack_ratio',0,2,false);num(ai.retreat_ratio??0,'content.ai.retreat_ratio',0,2,false);
   if(!['weakest','income','nearest'].includes(ai.targets||'weakest'))add('content.ai.targets','Unknown targeting rule');
   if(!Array.isArray(ai.priorities||[])||(ai.priorities||[]).length>32)add('content.ai.priorities','Maximum 32 rules');
   else (ai.priorities||[]).forEach((p,i)=>{const path=`content.ai.priorities[${i}]`;keys(p,['action','id','reserve','max_level'],path);if(!['research','construct','recruit','upgrade','business'].includes(p.action))add(path+'.action','Unknown action');const ids=p.action==='research'?techs:p.action==='construct'?buildings:units;if(p.action!=='business'&&!ids.includes(p.id))add(path+'.id','Unknown reference');num(p.reserve??0,path+'.reserve',0,100000000);num(p.max_level??10,path+'.max_level',1);});
   for(const [key,color] of Object.entries(c.theme||{})){if(!['ink','muted','accent','ocean','unknown'].includes(key)||typeof color!=='string'||!/^#?(?:[a-f\d]{3}|[a-f\d]{4}|[a-f\d]{6}|[a-f\d]{8})$/i.test(color))add('content.theme.'+key,'Invalid theme color');}
   for(const [locale,catalog] of Object.entries(c.translations||{})){if(!['ru','en'].includes(locale)||!object(catalog)||Object.keys(catalog).length>512){add('content.translations.'+locale,'Invalid translation catalog');continue;}for(const [key,value]of Object.entries(catalog)){if(typeof value!=='string'||key.length>1024||value.length>1024)add('content.translations.'+locale+'.'+key,'Expected text, max 1024 characters');else if((key.match(/%(?:0?\d+)?[dsf]/g)||[]).join()!==(value.match(/%(?:0?\d+)?[dsf]/g)||[]).join())add('content.translations.'+locale+'.'+key,'Format placeholders differ');}}
   for(const [key,asset] of Object.entries(c.assets||{})){if(!object(asset)||typeof asset.data!=='string'||asset.data.length>262144||!['image/png','audio/wav'].includes(asset.mime))add('content.assets.'+key,'Invalid media object / size');if(key.startsWith('flag:')&&!countries.includes(Number(key.slice(5))))add('content.assets.'+key,'Unknown flag country');}
   if(Object.keys(c.assets||{}).length>64)add('content.assets','Maximum 64 resources');
   return issues;
 }
 function compare(before,after){
   const changes=[];const walk=(a,b,path)=>{if(JSON.stringify(a)===JSON.stringify(b))return;if(object(a)&&object(b)){for(const k of new Set([...Object.keys(a),...Object.keys(b)]))walk(a[k],b[k],path?path+'.'+k:k);}else changes.push({path,before:a,after:b});};walk(before,after,'');
   const risks=[];for(const kind of ['units','buildings','technologies','events']){const ids=new Set((after.content?.[kind]||[]).map(x=>x.id));for(const x of before.content?.[kind]||[])if(!ids.has(x.id))risks.push('Removed '+kind+': '+x.id);}
   if(JSON.stringify((before.content?.units||[]).map(x=>x.id))!==JSON.stringify((after.content?.units||[]).map(x=>x.id)))risks.push('Troop vector order changed');
   if(JSON.stringify(before.content?.map)!==JSON.stringify(after.content?.map))risks.push('Map / country IDs changed');
   if(before.id!==after.id||before.game_version!==after.game_version)risks.push('Mod identity or game version changed');
   return {changes,risks,savePolicy:'Exact package profile required. No automatic save migration.'};
 }
 function compose(documents){
   const d={api:2,id:'profile',name:'Combined profile',version:'1',game_version:'0.3.0',changes:{},content:{}};
   for(const mod of documents){d.changes={...d.changes,...mod.network_balance,...mod.changes};for(const [key,value]of Object.entries(mod.content||{})){if(!['units','buildings','technologies','events','panels','translations','theme','assets','scenario','victory','map','ai'].includes(key))throw Error(mod.id+'.content.'+key+': unknown field');
     if(['units','buildings','technologies','events','panels'].includes(key)){if(!Array.isArray(value))throw Error(mod.id+'.content.'+key+': expected array');d.content[key]=[...(d.content[key]||[]),...clone(value)];}
     else if(key==='translations'){d.content.translations??={};for(const [locale,catalog]of Object.entries(value))d.content.translations={...d.content.translations,[locale]:{...d.content.translations[locale],...clone(catalog)}};}
     else if(['theme','assets'].includes(key))d.content[key]={...d.content[key],...clone(value)};else d.content[key]=clone(value);
   }}return d;
 }
 function removeCountry(doc,id,defaultAtlas){
   const d=clone(doc);d.content??={};const map=d.content.map||clone(defaultAtlas);if(map.length<=3)throw Error('A map needs at least 3 countries');
   const c=d.content,s=c.scenario||{},g=c.victory||{};
   if(Object.keys(s.starts||{}).includes(String(id))||Object.keys(s.armies||{}).includes(String(id))||Object.values(s.starts||{}).some(x=>x.owned?.includes(id))||(s.alliances||[]).some(x=>x.includes(id))||g.countries?.includes(id)||(c.events||[]).some(e=>e.conditions?.country_id===id||e.conditions?.owns?.includes(id)||e.actions.some(a=>a.country_id===id))||c.assets?.['flag:'+id])throw Error('Country is referenced by scenario/events/goal/media. Remove those references first.');
   const remap=x=>x>id?x-1:x,refs=list=>list.filter(x=>x!==id).map(remap);
   map.splice(id,1);map.forEach((country,i)=>{country.id=i;country.sovereign=country.sovereign===id?i:remap(country.sovereign);for(const key of ['neighbors','dependencies','enclave_hosts'])country[key]=refs(country[key]||[]);});
   for(const key of ['starts','armies'])if(s[key])s[key]=Object.fromEntries(Object.entries(s[key]).map(([key,value])=>[remap(Number(key)),value]));
   for(const start of Object.values(s.starts||{}))if(start.owned)start.owned=refs(start.owned);
   if(s.default_home!==undefined)s.default_home=s.default_home===id?0:remap(s.default_home);
   if(s.alliances)s.alliances=s.alliances.map(refs);if(g.countries)g.countries=refs(g.countries);
   for(const e of c.events||[]){if(e.conditions?.country_id!==undefined)e.conditions.country_id=remap(e.conditions.country_id);if(e.conditions?.owns)e.conditions.owns=refs(e.conditions.owns);for(const a of e.actions)if(a.country_id!==undefined)a.country_id=remap(a.country_id);}
   if(c.assets)c.assets=Object.fromEntries(Object.entries(c.assets).map(([key,value])=>[key.startsWith('flag:')?'flag:'+remap(Number(key.slice(5))):key,value]));
   c.map=map;return d;
 }
 function testEvents(d,input,trigger,country=-1){
   const state=clone({coins:0,owned:[],researches:[],flags:{},fired:{},elapsed:0,random_state:71,result:'',messages:[],...input,units:{...Object.fromEntries(branches(d).map(x=>[x,0])),...input.units}});const trace=[];let budget=64;
   if(!number(state.coins,0,1e12,false)||!number(state.elapsed,0,1e9)||!number(state.random_state,1,2147483646)||!Array.isArray(state.owned)||!Array.isArray(state.researches)||!object(state.flags)||!object(state.fired)||Object.values(state.units).some(x=>!number(x,0,1e8)))throw Error('Invalid preview state: coins/elapsed/random_state/owned/researches/flags/fired/units');
   for(const e of d.content?.events||[]){if(e.when!==trigger)continue;const c=e.conditions||{};const reasons=[];
     if(state.fired[e.id]!==undefined&&((e.once??true)||state.elapsed-state.fired[e.id]<(e.cooldown??1)))reasons.push('once/cooldown');
     if(c.country_id!==undefined&&c.country_id!==country)reasons.push('country_id');
     if(state.elapsed<(c.elapsed_min||0))reasons.push('elapsed_min');if(state.coins<(c.coins_min||0))reasons.push('coins_min');
     for(const id of c.owns||[])if(!state.owned.includes(id))reasons.push('owns:'+id);
     for(const id of c.researches||[])if(!state.researches.includes(id))reasons.push('researches:'+id);
     for(const [k,v]of Object.entries(c.flags||{}))if(state.flags[k]!==v)reasons.push('flag:'+k);
     if(!reasons.length&&(c.chance??100)<100){state.random_state=state.random_state*48271%2147483647;if(state.random_state%100>=c.chance)reasons.push('chance');}
     if(!reasons.length&&e.actions.length>budget){trace.push({id:e.id,fired:false,reasons:['action budget']});break;}
     trace.push({id:e.id,fired:!reasons.length,reasons});if(reasons.length)continue;budget-=e.actions.length;state.fired[e.id]=state.elapsed;
     for(const a of e.actions){switch(a.type){case'add_coins':state.coins=Math.max(0,Math.min(1e12,state.coins+(a.amount||0)));break;case'add_units':{const k=a.unit||'infantry';state.units[k]=Math.max(0,Math.min(1e8,state.units[k]+(a.amount||0)));break;}case'show_message':state.messages.push(a.text||'');break;case'set_flag':state.flags[a.key]=a.value;break;case'grant_research':if(!state.researches.includes(a.technology))state.researches.push(a.technology);break;case'capture_country':if(!state.owned.includes(a.country_id))state.owned.push(a.country_id);break;case'release_country':state.owned=state.owned.filter(x=>x!==a.country_id);break;case'win':case'lose':state.result=a.type;break;}}
     if(state.result)break;
   }return {state,trace,budget};
 }
 const api={clone,object,id,number,branches,triggers,actions,fields,ringIssues,diagnose:(...args)=>{try{return diagnose(...args);}catch(e){return [{path:'content',severity:'error',message:'Malformed nested field: '+e.message}];}},compare,compose,removeCountry,testEvents};
 if(typeof module!=='undefined')module.exports=api;else root.AtlasStudio=api;
})(typeof globalThis!=='undefined'?globalThis:this);
