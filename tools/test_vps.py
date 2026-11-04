"""Run two clients, isolated rooms and a full dedicated-server restart."""
from pathlib import Path
import os
import socket
import subprocess
import tempfile
import time
import sys

root = Path(__file__).resolve().parent.parent
engine = root / "tools/godot-4.8-beta2/Godot_v4.8-beta2_win64.exe"
processes = []
logs = []


def launch(arguments, env):
    log = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
    logs.append(log)
    display = [] if "--native-ui" in sys.argv and "tests/test_vps_ui.gd" in arguments else ["--headless"]
    if arguments == ["--", "--server"] and "--server-pack" in sys.argv:
        pack = Path(sys.argv[sys.argv.index("--server-pack") + 1]).resolve()
        arguments = ["--main-pack", str(pack)] + arguments
    process = subprocess.Popen([str(engine)] + display + ["--path", str(root)] + arguments,
                               cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(process)
    return process, log


def ready(process):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError("Dedicated server exited before listening")
        try:
            with socket.create_connection(("127.0.0.1", 30760), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError("Dedicated server did not listen")


try:
    with tempfile.TemporaryDirectory(prefix="atlas-vps-") as temporary:
        folder = Path(temporary)
        data = folder / "data"
        data.mkdir()
        env = dict(os.environ, ATLAS_TEST_DIR=str(folder), ATLAS_DATA_DIR=str(data), ATLAS_PORT="30760", ATLAS_MAX_ROOMS="2")
        if '--mobile-ui' in sys.argv:env['ATLAS_MOBILE_UI']='1'
        if '--english' in sys.argv:env['ATLAS_TEST_LANGUAGE']='en'
        server, server_log = launch(["--", "--server"], env)
        ready(server)
        clients = [launch(["--script", "tests/vps_peer.gd", "--", role], env) for role in ("admin", "guest")]
        deadline = time.monotonic() + 55
        while not all((folder / f"{role}_restart_ready").exists() for role in ("admin", "guest")):
            if time.monotonic() > deadline or any(p.poll() is not None for p, _ in clients):
                raise RuntimeError("Clients failed before VPS restart")
            time.sleep(0.1)
        (data / ".stop").touch()
        server.wait(timeout=10)
        assert server.returncode == 0, "Server did not shut down cleanly"
        assert len(list(data.glob("session_*.json"))) == 2, "Both room saves must exist"
        (data / ".stop").unlink()
        server, _ = launch(["--", "--server"], env)
        ready(server)
        (folder / "restarted").touch()
        for process, _ in clients:
            process.wait(timeout=45)
            assert process.returncode == 0, "Client failed"
        ui, _ = launch(["--script", "tests/test_vps_ui.gd"], env)
        ui.wait(timeout=30)
        assert ui.returncode == 0, "VPS UI failed"
        (data / ".stop").touch()
        server.wait(timeout=10)
        assert not list(data.glob("session_*.json")), "Deleted rooms must not reappear after shutdown"
    failed = False
    for process, log in zip(processes, logs):
        log.seek(0)
        output = log.read()
        print(output)
        failed |= process.returncode != 0 or "ERROR:" in output
    raise SystemExit(1 if failed else 0)
except Exception:
    for log in logs:
        log.seek(0)
        print(log.read())
    raise
finally:
    for process in processes:
        if process.poll() is None:
            process.kill()
            process.wait()
    for log in logs:
        log.close()
