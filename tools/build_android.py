"""Export a native signed Android APK. Signing secrets stay outside the repository."""
from pathlib import Path
import json
import os
import secrets
import shutil
import subprocess
import zipfile
import re
from fetch_windows_template import EDITOR, main as ensure_godot

ROOT=Path(__file__).resolve().parent.parent

def run(command,env,log=None):
    result=subprocess.run([str(x) for x in command],cwd=ROOT,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
    if log:Path(log).write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode or 'ERROR:' in result.stdout + result.stderr:
        print(result.stdout,result.stderr)
        raise RuntimeError('Android build command failed')
    return result.stdout

def main():
    ensure_godot()
    sdk=os.environ.get('ATLAS_ANDROID_SDK') or os.environ.get('ANDROID_HOME')
    if (not sdk or not Path(sdk).exists()) and shutil.which('android'):
        info=subprocess.check_output(['android','info'],text=True,encoding='utf-8')
        sdk=next((line[5:].strip() for line in info.splitlines() if line.startswith('sdk: ')),None)
    if not sdk:raise RuntimeError('Set ATLAS_ANDROID_SDK to your Android SDK directory')
    jdk=os.environ.get('ATLAS_JAVA_SDK') or os.environ.get('JAVA_HOME')
    if (not jdk or not (Path(jdk)/'bin'/('keytool.exe' if os.name=='nt' else 'keytool')).exists()) and os.name=='nt':jdk='C:/Program Files/Android/Android Studio/jbr'
    if not jdk and shutil.which('java'):jdk=str(Path(shutil.which('java')).resolve().parent.parent)
    if not jdk:raise RuntimeError('Set ATLAS_JAVA_SDK to JDK 17 or newer')
    keytool=Path(jdk)/'bin'/('keytool.exe' if os.name=='nt' else 'keytool')
    if not keytool.exists():raise RuntimeError('JDK keytool not found')
    env=dict(os.environ,ATLAS_ANDROID_SDK=str(sdk),ATLAS_JAVA_SDK=str(jdk),JAVA_HOME=str(jdk))
    output=ROOT/'build/android'
    output.mkdir(parents=True,exist_ok=True)
    (ROOT/'build/.gdignore').touch()
    key_dir=Path.home()/'.atlas/signing'
    key_dir.mkdir(parents=True,exist_ok=True)
    key_file=key_dir/'android-release.jks'
    config_file=key_dir/'android-release.json'
    if not config_file.exists():
        if key_file.exists():raise RuntimeError('Signing keystore exists without its configuration; restore the signing backup')
        config_file.write_text(json.dumps({'password':secrets.token_hex(16),'alias':'atlas'}),encoding='utf-8')
        if os.name!='nt':config_file.chmod(0o600)
    config=json.loads(config_file.read_text(encoding='utf-8'))
    env['ATLAS_KEY_PASSWORD']=config['password']
    if not key_file.exists():
        run([keytool,'-genkeypair','-keystore',key_file,'-alias',config['alias'],'-storepass:env','ATLAS_KEY_PASSWORD',
             '-keypass:env','ATLAS_KEY_PASSWORD','-keyalg','RSA','-keysize','3072','-validity','10000',
             '-dname','CN=ATLAS, O=ATLAS','-noprompt'],env)
    env.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(key_file),GODOT_ANDROID_KEYSTORE_RELEASE_USER=config['alias'],
               GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=config['password'])
    # Preserve all editor preferences while configuring only the two SDK paths.
    editor_dir=Path(os.environ.get('APPDATA',Path.home()/'.config'))/'Godot'
    settings_file=editor_dir/'editor_settings-4.8.tres'
    editor_dir.mkdir(parents=True,exist_ok=True)
    settings=settings_file.read_text(encoding='utf-8') if settings_file.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
    for name,value in [('export/android/android_sdk_path',sdk),('export/android/java_sdk_path',jdk)]:
        line=name+' = '+json.dumps(str(value).replace('\\','/'))
        if re.search('^'+re.escape(name)+r'\s*=',settings,re.M):settings=re.sub('^'+re.escape(name)+r'\s*=.*$',lambda _:line,settings,flags=re.M)
        else:settings+='\n'+line+'\n'
    settings_file.write_text(settings,encoding='utf-8')
    apk=output/'Atlas-Android-v0.3.0.apk'
    run([EDITOR,'--headless','--path',ROOT,'--export-release','Android',apk],env,output/'export.log')
    build_tools=sorted((Path(sdk)/'build-tools').iterdir(),key=lambda p:tuple(int(x) for x in p.name.split('.') if x.isdigit()))[-1]
    signer=build_tools/('apksigner.bat' if os.name=='nt' else 'apksigner')
    # Run the jar directly to keep the JDK path independent of the caller's PATH.
    verification=run([Path(jdk)/'bin'/('java.exe' if os.name=='nt' else 'java'),'-jar',build_tools/'lib/apksigner.jar',
                      'verify','--verbose','--print-certs',apk],env,output/'verification.log')
    if 'DOES NOT VERIFY' in verification:raise RuntimeError('APK signature verification failed')
    with zipfile.ZipFile(apk) as bundle:
        for abi in ['armeabi-v7a','arm64-v8a','x86','x86_64']:
            if 'lib/'+abi+'/libgodot_android.so' not in bundle.namelist():
                raise RuntimeError('Missing native Android library: '+abi)
        if any('WebView' in n for n in bundle.namelist()):raise RuntimeError('Unexpected WebView component')
    shutil.copyfile(apk,ROOT/'build/Atlas-Android.apk')
    print('Ready:',apk)
    print('Signing key backup directory:',key_dir)

if __name__=='__main__':main()
