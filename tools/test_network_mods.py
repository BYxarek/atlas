"""Transfer the SAME .atlasmod through LAN, VPS and PHP, then reconnect in a new process."""
from pathlib import Path
import os
import json
import shutil
import socket
import subprocess
import tempfile
import time
from fetch_windows_template import EDITOR
from fetch_php import php_binary

ROOT = Path(__file__).resolve().parents[1]
processes = []
logs = []

def launch(command, env):
    log = tempfile.TemporaryFile(mode='w+', encoding='utf-8')
    process = subprocess.Popen([str(x) for x in command], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
    processes.append(process)
    logs.append(log)
    return process, log

def finish(pair):
    process, log = pair
    process.wait(timeout=35)
    log.seek(0)
    output = log.read()
    print(output)
    assert process.returncode == 0 and 'ERROR:' not in output and 'PASS:' in output, 'Mod peer failed'

def peer(role, kind, env):
    return launch([EDITOR, '--headless', '--path', ROOT, '--script', 'tests/mod_peer.gd', '--', role, kind], env)

try:
    with tempfile.TemporaryDirectory(prefix='atlas-network-mods-') as temporary:
        base = Path(temporary)
        package = base/'starter.atlasmod'
        source = base/'source'
        shutil.copytree(ROOT/'examples/starter-economy',source)
        manifest=json.loads((source/'mod.json').read_text(encoding='utf-8'))
        manifest['network_balance']=json.loads((source/'files/assets/balance.json').read_text(encoding='utf-8'))
        portable=json.loads((ROOT/'examples/frontier/mod.json').read_text(encoding='utf-8'))
        manifest['api']=2
        manifest['changes']={'start_coins':1000}
        manifest['content']={key:value for key,value in portable['content'].items() if key not in ('map','scenario')}
        (source/'mod.json').write_text(json.dumps(manifest),encoding='utf-8')
        (source/'files/padding.txt').write_text('x'*150000,encoding='ascii')
        build = subprocess.run([str(EDITOR), '--headless', '--path', str(ROOT), '--script', 'tools/build_mod.gd', '--',
                                str(source), str(package)], cwd=ROOT, capture_output=True, text=True, timeout=30)
        assert build.returncode == 0 and package.exists() and 'ERROR:' not in build.stdout+build.stderr, build.stdout+build.stderr
        assert package.stat().st_size>65536, 'Fixture must exercise multiple chunks'
        for kind in ('lan', 'vps', 'php'):
            folder = base/kind
            source = folder/'host_mods'
            cache = folder/'client_mods'
            source.mkdir(parents=True)
            cache.mkdir()
            shutil.copy2(package, source/package.name)
            env = dict(os.environ, ATLAS_TEST_DIR=str(folder), ATLAS_MODS_DIR=str(source))
            if kind == 'php':
                site = folder/'site'
                site.mkdir()
                for file in (ROOT/'hosting').iterdir():
                    if file.is_file(): shutil.copy2(file, site/file.name)
                (site/'network_mods').mkdir()
                shutil.copy2(package, site/'network_mods'/package.name)
                server = launch([php_binary(), '-S', '127.0.0.1:31761', '-t', site], env)
                deadline = time.monotonic()+10
                while True:
                    try:
                        with socket.create_connection(('127.0.0.1',31761),timeout=.2): break
                    except OSError:
                        if time.monotonic()>deadline: raise TimeoutError('PHP server startup')
                        time.sleep(.1)
            else:
                server = peer('host',kind,env)
                deadline=time.monotonic()+10
                while not (folder/'listening').exists():
                    if time.monotonic()>deadline or server[0].poll() is not None: raise TimeoutError('Native mod host startup')
                    time.sleep(.1)
            client_env=dict(env,ATLAS_MODS_DIR=str(cache))
            finish(peer('download',kind,client_env))
            assert len(list((cache/'cache').glob('*.atlasmod')))==1, 'Missing downloaded package'
            assert next((cache/'cache').glob('*.atlasmod')).read_bytes()==package.read_bytes(), 'Different mod package on '+kind
            finish(peer('resume',kind,client_env))
            if kind!='php': finish(server)
            else:
                server[0].terminate()
                server[0].wait(timeout=10)
        print('PASS: one package, three transports, explicit offer, download, restart, admission and shared simulation')
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
    for log in logs: log.close()
