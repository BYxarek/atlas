"""Fail on GDScript runtime errors as well as a failing process exit code."""
from pathlib import Path
import subprocess
import sys
from fetch_windows_template import EDITOR

ROOT = Path(__file__).resolve().parents[1]
result = subprocess.run([str(EDITOR), '--headless', '--path', str(ROOT), '--script', str(Path(sys.argv[1]).resolve()), *sys.argv[2:]],
                        cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
output = result.stdout + result.stderr
print(output, end='')
# Godot can report a runtime error and still exit zero after the test calls quit().
sys.exit(1 if result.returncode or 'ERROR:' in output or 'PASS:' not in output else 0)
