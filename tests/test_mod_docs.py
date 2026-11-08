"""Verify documentation links, reference coverage and builds from the downloaded standalone SDK."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
from zipfile import ZipFile
import hashlib
import json
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from fetch_windows_template import EDITOR
from build_mod_docs import BALANCE, RECIPES, main


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = set()
        self.links = []
        self.parameters = []
        self.h1 = 0
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, 'Duplicate anchor: ' + attrs['id']
            self.ids.add(attrs['id'])
        if 'data-parameter' in attrs:
            self.parameters.append(attrs['data-parameter'])
        if tag == 'h1': self.h1 += 1
        for key in ('href', 'src'):
            if key in attrs: self.links.append(attrs[key])


main()
site = ROOT / 'website'
pages = {path.resolve(): Page(path.read_text(encoding='utf-8')) for path in site.glob('*.html')}
for path, page in pages.items():
    assert page.h1 == 1, f'{path.name}: expected one title'
    for link in page.links:
        parsed = urlsplit(link)
        if parsed.scheme or parsed.netloc: continue
        target = (path.parent / unquote(parsed.path)).resolve() if parsed.path else path
        assert target.is_relative_to(site.resolve()), f'Link escapes site: {link}'
        assert target.exists(), f'{path.name}: missing {link}'
        if parsed.fragment and target in pages:
            assert unquote(parsed.fragment) in pages[target].ids, f'{path.name}: missing anchor {link}'
for name in ('mods.html', 'mods.ru.html'):
    assert pages[(site / name).resolve()].parameters == list(BALANCE), 'Reference differs from engine keys/order'
assert json.loads((site/'examples/balance.default.json').read_text(encoding='utf-8')) == BALANCE

with tempfile.TemporaryDirectory(prefix='atlas-sdk-docs-') as temporary:
    sdk = Path(temporary)
    with ZipFile(site/'examples/atlas-mod-sdk.zip') as archive:
        archive.extractall(sdk)
    for id, (changes, _, _) in RECIPES.items():
        output = sdk/'dist'/f'{id}.atlasmod'
        result = subprocess.run([str(EDITOR), '--headless', '--path', str(sdk), '--script', 'tools/build_mod.gd', '--',
                                 f'examples/{id}', str(output)], cwd=sdk, capture_output=True, text=True,
                                encoding='utf-8', errors='replace', timeout=30)
        assert result.returncode == 0 and 'ERROR:' not in result.stdout+result.stderr, result.stdout+result.stderr
        data = output.read_bytes()
        assert data[:8] == b'ATLASMOD'
        length = struct.unpack('<I', data[8:12])[0]
        manifest = json.loads(data[12:12+length])
        pck = data[12+length:]
        assert pck[:4] == b'GDPC' and hashlib.sha256(pck).hexdigest() == manifest['pck_sha256']
        assert manifest['network_balance'] == BALANCE | changes, f'{id}: example differs from explanation'
        assert manifest['id'] == id and manifest['game_version'] == '0.3.0'
    result = subprocess.run([str(EDITOR), '--headless', '--path', str(sdk), '--script', 'tools/build_mod.gd', '--',
                             'examples/frontier', str(sdk/'dist/frontier.atlasmod')], cwd=sdk, capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=30)
    assert result.returncode == 0 and 'ERROR:' not in result.stdout+result.stderr, result.stdout+result.stderr
    package=(sdk/'dist/frontier.atlasmod').read_bytes()
    index=json.dumps({'version':1,'mods':[{'id':'frontier','version':'1.0.0','size':len(package),'sha256':hashlib.sha256(package).hexdigest()}]}).encode()
    (sdk/'dist/set.atlaspack').write_bytes(b'ATLASSET'+struct.pack('<I',len(index))+index+package)
    result=subprocess.run([str(EDITOR),'--headless','--path',str(sdk),'--script','tools/mod_set.gd','--','unpack',str(sdk/'dist/set.atlaspack'),str(sdk/'unpacked')],cwd=sdk,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30)
    assert result.returncode==0 and 'ERROR:' not in result.stdout+result.stderr,result.stdout+result.stderr
    assert (sdk/'unpacked/00_frontier.atlasmod').read_bytes()==package
    (sdk/'plan.json').write_text(json.dumps(dict(sessions=1,seconds=8,bots=2,seed=2026)),encoding='utf-8')
    result=subprocess.run([sys.executable,str(sdk/'tools/test_mod_balance.py'),'--godot',str(EDITOR),'--config',str(sdk/'plan.json'),'--output',str(sdk/'report.json'),str(sdk/'dist/frontier.atlasmod')],cwd=sdk,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=30)
    assert result.returncode==0 and 'ERROR:' not in result.stdout+result.stderr,result.stdout+result.stderr
    assert json.loads((sdk/'report.json').read_text())['summary']['games']==1
print('PASS: all website links/anchors, every balance parameter and all three SDK examples built independently')
