'use strict';
(async () => {
  const $ = id => document.getElementById(id);
  const ru = document.documentElement.lang === 'ru';
  const t = (a,b) => ru ? a : b;
  const report = (message, error=false) => { $('status').textContent=message; $('status').classList.toggle('error',error); };
  const guard = fn => async (...args) => { try { await fn(...args); } catch(e) { report(e.message,true); } };
  const response = await fetch('mod-studio-data.json');
  if (!response.ok) throw Error('Cannot load editor data');
  const data = await response.json();
  let doc = structuredClone(data.templates.patch);
  const object = v => v && typeof v === 'object' && !Array.isArray(v);
  function validate(d) {
    if (!object(d)||d.api!==2||!/^[a-z0-9_-]{1,64}$/.test(d.id)||typeof d.name!=='string'||!d.name.length||typeof d.version!=='string'||d.game_version!=='0.2.0') throw Error('Invalid API 2 identity / game version');
    if (!object(d.changes||{})||!object(d.content||{})) throw Error('changes/content must be objects');
    for (const [key,value] of Object.entries(d.changes||{})) {
      if (!(key in data.balance)) throw Error('Unknown balance field: '+key);
      const values=Array.isArray(value)?value:[value];
      if (Array.isArray(data.balance[key]) && (!Array.isArray(value)||value.length!==3)) throw Error(key+': expected three values');
      if (values.some(x=>typeof x!=='number'||!Number.isFinite(x)||x<0||x>1000000)) throw Error('Invalid number: '+key);
    }
    for (const key of Object.keys(d.content||{})) if (!['units','buildings','technologies','events','panels','scenario','victory','map','translations','theme','assets'].includes(key)) throw Error('Unknown content: '+key);
    for (const [key,max] of Object.entries({units:13,buildings:32,technologies:32,events:128,panels:16})) {
      const entries=d.content?.[key]||[];
      if (!Array.isArray(entries)||entries.length>max) throw Error('Invalid catalog / limit: '+key);
      const ids=new Set();
      for(const entry of entries) {if(!object(entry)||typeof entry.id!=='string'||!/^[a-z0-9_-]{1,64}$/.test(entry.id)||ids.has(entry.id))throw Error('Invalid/duplicate ID in '+key);ids.add(entry.id);}
    }
    const events=d.content?.events||[];
    for(const e of events)if(!['start','tick','country_captured','research_completed','building_built','mission_completed'].includes(e.when)||!Array.isArray(e.actions)||e.actions.length<1||e.actions.length>16||e.actions.some(a=>!['add_coins','add_units','show_message','set_flag','grant_research','capture_country','release_country','win','lose'].includes(a.type)))throw Error('Invalid event: '+e.id);
    if(d.content?.map && (!Array.isArray(d.content.map)||d.content.map.length<3||d.content.map.length>512))throw Error('Map: expected 3–512 countries');
    return d;
  }
  function read(){doc=validate(JSON.parse($('source').value));return doc;}
  function write(){ $('source').value=JSON.stringify(doc,null,2);render(); }
  const atlas=()=>doc.content?.map||data.atlas;
  function render(){
    $('balance-fields').replaceChildren();
    for(const [key,base] of Object.entries(data.balance)) {
      if(key==='version')continue;
      const label=document.createElement('label');label.textContent=key;
      const input=document.createElement('input');input.value=JSON.stringify(doc.changes?.[key]??base);input.setAttribute('aria-label',key);
      input.oninput=guard(()=>{read();const v=JSON.parse(input.value);doc.changes??={};if(JSON.stringify(v)===JSON.stringify(base))delete doc.changes[key];else doc.changes[key]=v;validate(doc);$('source').value=JSON.stringify(doc,null,2);});
      label.append(input);$('balance-fields').append(label);
    }
    const old=$('country').value;$('country').replaceChildren();
    atlas().forEach((c,i)=>{const o=document.createElement('option');o.value=i;o.textContent=i+' — '+(ru?c.name:c.english||c.name);$('country').append(o);});
    $('country').value=old!==''&&Number(old)<atlas().length?old:String(doc.content?.scenario?.default_home??0);
    draw();entries();
    $('preview').textContent=JSON.stringify({units:3+(doc.content?.units||[]).length,countries:atlas().length,victory:doc.content?.victory||{type:'world'}},null,2);
  }
  function draw(){
    const svg=$('scenario-map');svg.replaceChildren();
    atlas().forEach((c,i)=>{const p=document.createElementNS('http://www.w3.org/2000/svg','path');p.setAttribute('d',(c.rings||[]).map(r=>'M'+r.map(([x,y])=>x+','+(-y)).join('L')+'Z').join(''));p.classList.toggle('selected',i===Number($('country').value));p.onclick=()=>{$('country').value=i;draw();};const title=document.createElementNS(svg.namespaceURI,'title');title.textContent=i+' '+c.name;p.append(title);svg.append(p);});
    const start=doc.content?.scenario?.starts?.[$('country').value];
    $('country-coins').value=start?.coins??doc.changes?.start_coins??data.balance.start_coins;
    $('country-owned').value=(start?.owned||[]).join(',');
  }
  const examples={units:{id:'cannon',name:'Cannon',cost:40,weight:6,recruit:2,start:0,requires:[]},buildings:{id:'forge',name:'Forge',cost:25,income:3,requires:[]},technologies:{id:'metallurgy',name:'Metallurgy',cost:20,requires:[],unit:'infantry',bonus:.1,income:1},events:{id:'welcome',when:'start',once:true,actions:[{type:'add_coins',amount:100}]},panels:{id:'briefing',title:'Briefing',text:'Welcome',action:'economy'}};
  function entries(){const kind=$('entry-kind').value;const list=$('content-list');list.replaceChildren();for(const entry of doc.content?.[kind]||[]){const edit=document.createElement('button');edit.textContent=entry.id;edit.onclick=()=>{$('entry-json').value=JSON.stringify(entry,null,2);};const remove=document.createElement('button');remove.textContent=t('Удалить ','Delete ')+entry.id;remove.onclick=guard(()=>{read();doc.content[kind]=doc.content[kind].filter(x=>x.id!==entry.id);write();});list.append(edit,remove);}}
  function download(bytes,name,type){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([bytes],{type}));a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);}
  $('entry-kind').onchange=()=>{entries();$('entry-json').value=JSON.stringify(examples[$('entry-kind').value],null,2);};
  $('country').onchange=draw;
  $('apply-json').onclick=guard(()=>{read();write();report(t('JSON применён','JSON applied'));});
  $('check').onclick=guard(()=>{read();report(t('Предварительная проверка пройдена. Выполните проверку SDK перед выпуском.','Preliminary checks passed. Run SDK validation before publishing.'));});
  $('load-template').onclick=guard(()=>{if(confirm(t('Заменить текущий документ?','Replace current document?'))){doc=structuredClone(data.templates[$('template').value]);write();}});
  $('save-start').onclick=guard(()=>{read();const id=Number($('country').value),coins=Number($('country-coins').value),owned=$('country-owned').value.split(',').map(x=>x.trim()).filter(Boolean).map(Number);if(!Number.isInteger(coins)||coins<0||coins>100000000||owned.some(x=>!Number.isInteger(x)||x<0||x>=atlas().length))throw Error('Invalid scenario resources');doc.content??={};doc.content.scenario??={};doc.content.scenario.starts??={};doc.content.scenario.starts[id]={...doc.content.scenario.starts[id],coins,owned};doc.content.scenario.default_home=id;write();});
  $('copy-map').onclick=guard(()=>{read();doc.content??={};doc.content.map=structuredClone(atlas());write();});
  $('save-entry').onclick=guard(()=>{read();const key=$('entry-kind').value,entry=JSON.parse($('entry-json').value);doc.content??={};doc.content[key]??=[];const i=doc.content[key].findIndex(x=>x.id===entry.id);if(i<0)doc.content[key].push(entry);else doc.content[key][i]=entry;validate(doc);write();});
  $('add-media').onchange=guard(async e=>{const file=e.target.files[0];if(!file)return;read();if(file.size>196608)throw Error('Resource exceeds 192 KiB');const bytes=new Uint8Array(await file.arrayBuffer()),key=$('media-key').value;let mime;if(/^flag:[0-9]+$/.test(key)){mime='image/png';const bitmap=await createImageBitmap(file);const valid=bitmap.width<=1024&&bitmap.height<=1024;bitmap.close();if(!valid||bytes[0]!==137||bytes[1]!==80)throw Error('Expected PNG, max 1024×1024');}else if(/^sound:[a-z0-9_-]+$/.test(key)){mime='audio/wav';if(new TextDecoder().decode(bytes.slice(0,4))!=='RIFF'||new TextDecoder().decode(bytes.slice(8,12))!=='WAVE')throw Error('Expected WAV');}else throw Error('Use flag:COUNTRY_ID or sound:CUE');let binary='';for(const b of bytes)binary+=String.fromCharCode(b);doc.content??={};doc.content.assets??={};doc.content.assets[key]={mime,data:btoa(binary)};write();});
  $('export-json').onclick=guard(()=>{read();download(JSON.stringify(doc,null,2),doc.id+'.json','application/json');});
  $('export-mod').onclick=guard(async()=>{read();const pck=Uint8Array.from(atob(data.empty_pck),x=>x.charCodeAt(0));const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',pck)),x=>x.toString(16).padStart(2,'0')).join('');const manifest=new TextEncoder().encode(JSON.stringify({...doc,pck_sha256:hash}));if(manifest.length>4194304)throw Error('Manifest exceeds 4 MiB');const bytes=new Uint8Array(12+manifest.length+pck.length);bytes.set(new TextEncoder().encode('ATLASMOD'));new DataView(bytes.buffer).setUint32(8,manifest.length,true);bytes.set(manifest,12);bytes.set(pck,12+manifest.length);download(bytes,doc.id+'.atlasmod','application/octet-stream');report(t('Пакет собран','Package built'));});
  $('import').onchange=guard(async e=>{const file=e.target.files[0];if(!file)return;if(file.size>67108864)throw Error('File exceeds 64 MiB');const bytes=new Uint8Array(await file.arrayBuffer());let next;if(file.name.endsWith('.atlasmod')){if(new TextDecoder().decode(bytes.slice(0,8))!=='ATLASMOD')throw Error('Invalid container');const n=new DataView(bytes.buffer).getUint32(8,true);if(n>4194304||12+n>bytes.length)throw Error('Invalid manifest length');const expected=Uint8Array.from(atob(data.empty_pck),x=>x.charCodeAt(0));const pck=bytes.slice(12+n);if(pck.length!==expected.length||pck.some((b,i)=>b!==expected[i]))throw Error('Editor imports data-only packages with the standard empty PCK; use JSON for native packages');next=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes.slice(12,12+n)));}else next=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));validate(next);doc=next;write();report(t('Файл загружен','File loaded'));});
  write();$('entry-kind').onchange();report(t('Редактор готов','Editor ready'));
})().catch(e=>{document.getElementById('status').textContent=e.message;document.getElementById('status').classList.add('error');});
