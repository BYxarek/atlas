"""Compare the portable interpreter against PHP using one identical package and replay."""
from pathlib import Path
import os
import json
import shutil
import subprocess
import tempfile
from fetch_windows_template import EDITOR
from fetch_php import php_binary

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='atlas-rules-') as temporary:
    folder=Path(temporary);site=folder/'site';mods=site/'network_mods';mods.mkdir(parents=True)
    for file in (ROOT/'hosting').iterdir():
        if file.is_file():shutil.copy2(file,site/file.name)
    def run(args,env=None):
        result=subprocess.run([str(x) for x in args],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=45)
        output=result.stdout+result.stderr
        print(output,end='')
        assert result.returncode==0 and 'ERROR:' not in output and 'PASS:' in output
    source=folder/'source';source.mkdir()
    doc=json.loads((ROOT/'examples/frontier/mod.json').read_text(encoding='utf-8'))
    doc['content']['ai']={'priorities':[{'action':'research','id':'metallurgy'},{'action':'research','id':'artillery'},{'action':'construct','id':'forge','max_level':2},{'action':'recruit','id':'cannon','max_level':20}], 'targets':'income','attack_ratio':1.1,'retreat_ratio':0.8}
    (source/'mod.json').write_text(json.dumps(doc),encoding='utf-8')
    run([EDITOR,'--headless','--path',ROOT,'--script','tools/build_mod.gd','--',source,mods/'frontier.atlasmod'])
    run([EDITOR,'--headless','--path',ROOT,'--script','tests/mod_rules_fixtures.gd'],dict(os.environ,ATLAS_TEST_DIR=str(folder),ATLAS_MODS_DIR=str(mods)))
    run([php_binary(),ROOT/'tests/test_mod_rules.php',site,folder/'fixtures.json'])
