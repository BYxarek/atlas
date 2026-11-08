"""Small end-to-end check of real simulation reports and non-destructive comparisons."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='atlas-balance-check-') as tmp:
    folder=Path(tmp);plan=folder/'plan.json';plan.write_text(json.dumps(dict(sessions=2,seconds=20,bots=2,seed=2026)))
    def run(output,*extra,success=True):
        result=subprocess.run([sys.executable,'tools/test_mod_balance.py','--config',str(plan),'--output',str(output),*extra,'website/examples/frontier.atlasmod'],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
        assert (result.returncode==0)==success,result.stdout+result.stderr
    a=folder/'a.json';b=folder/'b.json';run(a);run(b,'--baseline',str(a))
    first=json.loads(a.read_text());second=json.loads(b.read_text());assert first['summary']==second['summary'] and first['results']==second['results']
    assert second['comparison']['same_plan'] and second['comparison']['income_delta']==0
    original=a.read_bytes();run(a,success=False);assert a.read_bytes()==original
    print('PASS: seeded actual balance sessions, repeatability, comparison and report overwrite protection')
