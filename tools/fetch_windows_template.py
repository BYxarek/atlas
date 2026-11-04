"""Install the pinned Godot editor and matching export templates with verified hashes."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RELEASE = json.loads((ROOT / 'tools/godot_release.json').read_text(encoding='utf-8'))
VERSION = RELEASE['version']
ENGINE_DIR = ROOT / 'tools' / ('godot-' + VERSION)
EDITOR = ENGINE_DIR / ('Godot_v' + VERSION + '_win64.exe')


def matches(path, algorithm, expected):
    if not path.is_file():
        return False
    digest = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == expected


def main():
    cache = ROOT / 'build' / 'godot-downloads'
    cache.mkdir(parents=True, exist_ok=True)
    for name, archive in RELEASE['archives'].items():
        if all(matches(ROOT / entry['path'], 'sha256', entry['sha256']) for entry in archive['files'].values()):
            continue
        bundle = cache / name
        if not matches(bundle, 'sha512', archive['sha512']):
            url = f'https://github.com/godotengine/godot-builds/releases/download/{VERSION}/{name}'
            print('Downloading', name, flush=True)
            partial = bundle.with_suffix('.tmp')
            urllib.request.urlretrieve(url, partial)
            if not matches(partial, 'sha512', archive['sha512']):
                raise RuntimeError('Godot archive checksum mismatch: ' + name)
            partial.replace(bundle)
        with zipfile.ZipFile(bundle) as source:
            for member, entry in archive['files'].items():
                data = source.read(member)
                if hashlib.sha256(data).hexdigest() != entry['sha256']:
                    raise RuntimeError('Godot file checksum mismatch: ' + member)
                target = ROOT / entry['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = target.with_suffix('.tmp')
                temporary.write_bytes(data)
                temporary.replace(target)
    print('Verified Godot editor and templates:', VERSION)


if __name__ == '__main__':
    main()
