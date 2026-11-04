"""The pinned installer repairs stale templates and rejects corrupt downloads."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('godot_installer', Path(__file__).resolve().parents[1] / 'tools/fetch_windows_template.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_install_repair_and_reject_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'official.zip'
            payload = b'matching engine template'
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('templates/test.bin', payload)
            release = {'archives': {'test.zip': {
                'sha512': hashlib.sha512(source.read_bytes()).hexdigest(),
                'files': {'templates/test.bin': {'path': 'tools/test.bin', 'sha256': hashlib.sha256(payload).hexdigest()}}
            }}}
            target = root / 'tools/test.bin'
            with patch.object(installer, 'ROOT', root), patch.object(installer, 'RELEASE', release):
                with patch.object(installer.urllib.request, 'urlretrieve', side_effect=lambda url, dest: shutil.copyfile(source, dest)) as download:
                    installer.main()
                    self.assertEqual(target.read_bytes(), payload)
                    target.write_bytes(b'stale version')
                    installer.main()
                    self.assertEqual(target.read_bytes(), payload)
                    self.assertEqual(download.call_count, 1)
                (root / 'build/godot-downloads/test.zip').write_bytes(b'corrupt cache')
                target.write_bytes(b'stale version')
                with patch.object(installer.urllib.request, 'urlretrieve', side_effect=lambda url, dest: Path(dest).write_bytes(b'corrupt download')):
                    with self.assertRaisesRegex(RuntimeError, 'checksum mismatch'):
                        installer.main()
                self.assertEqual(target.read_bytes(), b'stale version')


if __name__ == '__main__':
    unittest.main()
