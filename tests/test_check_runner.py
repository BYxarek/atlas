"""A Godot runtime error must fail CI even when the script calls quit(0)."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
(ROOT / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='check-probe-', dir=ROOT / 'build') as temporary:
    script = Path(temporary) / 'probe.gd'
    script.write_text('''extends SceneTree
func broken():
    var data = {}
    print(data.missing)
func _initialize():
    broken()
    print("PASS: deliberate runtime-error probe")
    quit(0)
''')
    result = subprocess.run([sys.executable, str(ROOT / 'tools/test_godot.py'), str(script)], capture_output=True, text=True)
    assert result.returncode == 1 and 'SCRIPT ERROR:' in result.stdout, result.stdout + result.stderr
print('PASS: CI rejects runtime errors followed by quit(0)')
