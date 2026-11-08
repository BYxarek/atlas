"""Run reproducible games with the actual Godot simulation, then summarize/compare."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from fetch_windows_template import EDITOR

ROOT=Path(__file__).resolve().parents[1]


def summarize(data):
    factions=[f for game in data['results'] for f in game['factions']]
    homes={}
    for f in factions:
        row=homes.setdefault(str(f['home']),dict(games=0,wins=0,income=0,territories=0))
        row['games']+=1;row['wins']+=int(f['won']);row['income']+=f['mean_income'];row['territories']+=f['territories']
    for row in homes.values():
        row['win_rate']=row['wins']/row['games'];row['mean_income']=row.pop('income')/row['games'];row['mean_territories']=row.pop('territories')/row['games']
    units={unit:sum(f['units'][i] for f in factions)/len(factions) for i,unit in enumerate(data['units'])}
    recruitment={unit:sum(f['recruited_units'][i] for f in factions) for i,unit in enumerate(data['units'])}
    expansions=[f['first_expansion'] for f in factions if f['first_expansion']>=0]
    researches={id:sum(id in f['researches'] for f in factions) for id in sorted({id for f in factions for id in f['researches']})}
    summary=dict(games=len(data['results']),factions=len(factions),wins=sum(f['won'] for f in factions),mean_income=sum(f['mean_income'] for f in factions)/len(factions),by_home=homes,mean_units=units,recruited_units=recruitment,mean_first_expansion=sum(expansions)/len(expansions) if expansions else None,research_usage=researches)
    warnings=[]
    if summary['wins']==0:warnings.append('No victories within the time limit; extend the run before judging win rates.')
    if len(data['results'])<10:warnings.append('Small sample: use more sessions before drawing balance conclusions.')
    for unit,value in recruitment.items():
        if value==0:warnings.append('Unused troop branch: '+unit)
    if homes and max(r['win_rate'] for r in homes.values())-min(r['win_rate'] for r in homes.values())>.5:warnings.append('Large observed starting-country win-rate difference; compare equal sample sizes.')
    return summary,warnings


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mods',nargs='+',type=Path);parser.add_argument('--config',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--baseline',type=Path)
    parser.add_argument('--godot',type=Path,help='Godot executable; otherwise use PATH or the project-pinned editor')
    args=parser.parse_args();plan=json.loads(args.config.read_text(encoding='utf-8'))
    engine=args.godot.resolve() if args.godot else Path(shutil.which('godot') or EDITOR)
    if not engine.is_file():parser.error('Godot was not found. Install Godot 4.8-beta2 and pass --godot PATH')
    for key,low,high in [('sessions',1,100),('seconds',1,86400),('bots',2,16),('seed',1,2147483646)]:
        if type(plan.get(key)) is not int or not low<=plan[key]<=high:parser.error(f'{key}: expected integer {low}..{high}')
    if args.output.exists():parser.error('Output exists; use a new report path to preserve previous results')
    if not 1<=len(args.mods)<=32:parser.error('Expected 1–32 packages')
    with tempfile.TemporaryDirectory(prefix='atlas-mod-balance-') as temp:
        folder=Path(temp);mods=folder/'mods';mods.mkdir()
        for i,path in enumerate(args.mods):
            if path.suffix!='.atlasmod' or path.stat().st_size>67108864:parser.error('Expected .atlasmod package: '+str(path))
            shutil.copyfile(path,mods/f'{i:02d}_{path.name}')
        (folder/'plan.json').write_text(json.dumps(plan),encoding='utf-8')
        result=subprocess.run([str(engine),'--headless','--path',str(ROOT),'--script','tools/mod_balance.gd'],cwd=ROOT,env=dict(os.environ,ATLAS_MODS_DIR=str(mods),ATLAS_BALANCE_DIR=str(folder)),capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=3600)
        if result.returncode or 'ERROR:' in result.stdout+result.stderr:raise RuntimeError(result.stdout+result.stderr)
        data=json.loads((folder/'results.json').read_text());summary,warnings=summarize(data)
    report=dict(format='atlas-balance-report',version=1,plan=plan,summary=summary,warnings=warnings,**data)
    if args.baseline:
        before=json.loads(args.baseline.read_text(encoding='utf-8'))
        if before.get('format')!='atlas-balance-report':parser.error('Invalid baseline report')
        report['comparison']=dict(same_plan=before['plan']==plan,income_delta=summary['mean_income']-before['summary']['mean_income'],wins_delta=summary['wins']-before['summary']['wins'])
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as out:json.dump(report,out,ensure_ascii=False,indent=2)
    print('PASS: actual balance report:',args.output)


if __name__=='__main__':main()
