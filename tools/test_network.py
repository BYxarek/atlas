"""Exercise actual ENet and UDP discovery with two isolated Godot processes."""
from pathlib import Path
import subprocess
import time
import tempfile

root = Path(__file__).resolve().parent.parent
engine = root / "tools/Godot_v4.7.2-stable_win64.exe"
command = [str(engine), "--headless", "--path", str(root), "--script", "tests/network_peer.gd", "--"]
processes = []
logs = []
try:
    for role in ("host", "client"):
        log = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
        logs.append(log)
        processes.append((role, subprocess.Popen(command + [role], cwd=root, stdout=log, stderr=subprocess.STDOUT)))
    failed = False
    deadline = time.monotonic() + 45
    for (role, process), log in zip(processes, logs):
        process.wait(timeout=max(1, deadline - time.monotonic()))
        log.seek(0)
        output = log.read()
        print(f"{role}:\n{output}")
        failed |= process.returncode != 0 or "ERROR:" in output or "PASS:" not in output
    raise SystemExit(1 if failed else 0)
finally:
    for _, process in processes:
        if process.poll() is None:
            process.kill()
            process.wait()
    for log in logs:
        log.close()
