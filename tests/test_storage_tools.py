"""Exercise backup, replacement, rollback, and rejection without touching real rooms."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from fetch_php import php_binary

php = str(php_binary())
guard = '<?php http_response_code(404); exit; __halt_compiler(); ?>\n'
with tempfile.TemporaryDirectory(prefix='atlas-backup-') as temporary:
    folder = Path(temporary)
    state = folder / 'state.php'
    original = guard + '{"version":1,"rooms":{},"users":{}}'
    state.write_bytes(original.encode())
    snapshot = folder / 'snapshot.php'
    def run(action, path, succeeds=True):
        result = subprocess.run([php, str(ROOT / 'hosting/storage.php'), action, temporary, str(path)], capture_output=True)
        assert (result.returncode == 0) == succeeds, result.stderr
    run('backup', snapshot)
    assert snapshot.read_text() == original
    run('backup', snapshot, False)
    changed = guard + '{"version":1,"rooms":{},"users":{"new":{}}}'
    state.write_bytes(changed.encode())
    run('restore', snapshot)
    assert state.read_text() == original and (folder / 'before-restore.php').read_text() == changed
    invalid = folder / 'invalid.php'
    invalid.write_bytes((guard + '{"version":999,"rooms":{},"users":{}}').encode())
    run('restore', invalid, False)
    assert state.read_text() == original
    run('restore', folder / 'before-restore.php')
    assert state.read_text() == changed
print('PASS: backup, restore, rollback, overwrite and invalid-version protection')
