"""Check a fresh upload directory, real HTTP clients, cron and PHP worker restart."""
from pathlib import Path
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import sys
from fetch_php import php_binary

root=Path(__file__).resolve().parent.parent
php=php_binary()
godot=root/'tools/godot-4.8-beta2/Godot_v4.8-beta2_win64.exe'
processes=[]
logs=[]

def launch(command,env):
    log=tempfile.TemporaryFile(mode='w+',encoding='utf-8');logs.append(log)
    process=subprocess.Popen([str(x) for x in command],cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
    processes.append(process)
    return process

def wait_server(process):
    deadline=time.monotonic()+10
    while time.monotonic()<deadline:
        if process.poll() is not None:raise RuntimeError('PHP server exited')
        try:
            with socket.create_connection(('127.0.0.1',30761),timeout=.2):return
        except OSError:time.sleep(.1)
    raise TimeoutError('PHP startup')

try:
    # Refuse to run fixture clients against an unrelated server already on this port.
    with socket.socket() as probe:
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        probe.bind(('127.0.0.1', 30761))
    subprocess.run([str(godot),'--headless','--path',str(root),'--script','tests/php_fixtures.gd'],check=True)
    subprocess.run([str(php),'tests/test_php.php'],check=True)
    with tempfile.TemporaryDirectory(prefix='atlas-php-') as temporary:
        folder=Path(temporary);site=folder/'site';site.mkdir()
        for file in (root/'hosting').iterdir():
            if file.is_file():shutil.copy2(file,site/file.name)
        (site/'config.php').write_text("<?php return ['max_rooms'=>2,'lease_seconds'=>20,'poll_ms'=>750];",encoding='utf-8')
        env=dict(os.environ,ATLAS_PHP_TEST='1',ATLAS_TEST_DIR=str(folder))
        if '--mobile-ui' in sys.argv:env['ATLAS_MOBILE_UI']='1'
        if '--english' in sys.argv:env['ATLAS_TEST_LANGUAGE']='en'
        server=launch([php,'-S','127.0.0.1:30761','-t',site],env);wait_server(server)
        clients=[launch([godot,'--headless','--path',root,'--script','tests/vps_peer.gd','--',role],env) for role in ['admin','guest']]
        deadline=time.monotonic()+65
        while not all((folder/f'{role}_restart_ready').exists() for role in ['admin','guest']):
            if time.monotonic()>deadline or any(p.poll() is not None for p in clients):raise RuntimeError('HTTP clients failed before restart')
            time.sleep(.1)
        time.sleep(.4)
        server.terminate();server.wait(timeout=5)
        assert (site/'_data/state.php').exists(),'Persistent PHP save missing'
        subprocess.run([str(php),str(site/'cron.php')],env=env,check=True,capture_output=True)
        server=launch([php,'-S','127.0.0.1:30761','-t',site],env);wait_server(server)
        (folder/'restarted').touch()
        for p in clients:
            p.wait(timeout=60)
            assert p.returncode==0,'HTTP client failed'
        native='--native-ui' in sys.argv
        ui=launch([godot]+([] if native else ['--headless'])+['--path',root,'--script','tests/test_vps_ui.gd'],env)
        ui.wait(timeout=50);assert ui.returncode==0,'PHP UI failed'
        with urllib.request.urlopen('http://127.0.0.1:30761/') as response:assert response.status==200
        for path in ['_data/state.php','_data/backup.php','_data/lock.php','cron.php']:
            try:urllib.request.urlopen('http://127.0.0.1:30761/'+path);raise AssertionError('Private resource exposed: '+path)
            except urllib.error.HTTPError as error:assert error.code in (403,404)
        server.terminate();server.wait(timeout=5)
        workers=[launch([php,'tests/php_lock.php',site/'_data'],env) for _ in range(6)]
        for worker in workers:worker.wait(timeout=15);assert worker.returncode==0,'File lock worker failed'
        state=(site/'_data/state.php').read_text(encoding='utf-8').split('\n',1)[1]
        assert json.loads(state)['rooms']==[],'Deleted rooms returned after restart'
        assert json.loads(state)['test_counter']==60,'Concurrent workers lost an update'
    failed=False
    for p,log in zip(processes,logs):
        log.seek(0);output=log.read()
        if output.strip() and 'Development Server' not in output:print(output)
        failed|='ERROR:' in output or 'Fatal error:' in output or 'Warning:' in output
    if failed:raise RuntimeError('Errors in PHP integration logs')
    print('PASS: HTTP transport, persistence, cron, storage access protection and UI')
except Exception:
    for log in logs:
        log.seek(0);output=log.read()
        print('\n'.join(output.splitlines()[-12:]) if 'Development Server' in output else output)
    raise
finally:
    for p in processes:
        if p.poll() is None:p.kill();p.wait()
    for log in logs:log.close()
