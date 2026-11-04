"""Fetch only Windows x64 release from the official template ZIP, using HTTP ranges."""
import io
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VERSION = "4.7.2-stable"
URL = f"https://github.com/godotengine/godot/releases/download/{VERSION}/Godot_v{VERSION}_export_templates.tpz"
SIZE = 1281349702
ROOT = Path(__file__).resolve().parents[1]


def fetch(start, end):
    chunk_size = 2 * 1024 * 1024
    if end - start + 1 > chunk_size:
        parts = [(offset, min(offset + chunk_size - 1, end)) for offset in range(start, end + 1, chunk_size)]
        print(f"Downloading Windows template ({(end - start + 1) // 1024 // 1024} MB)...", flush=True)
        with ThreadPoolExecutor(max_workers=4) as pool:
            return b"".join(pool.map(lambda part: fetch(*part), parts))
    request = urllib.request.Request(URL, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(request, timeout=120) as response:
        if response.status != 206:
            raise RuntimeError("Server does not support partial downloads")
        data = response.read()
    if len(data) != end - start + 1:
        raise RuntimeError("Incomplete template download")
    return data


class RemoteZip(io.RawIOBase):
    def __init__(self):
        self.position = 0

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = offset + (0 if whence == 0 else self.position if whence == 1 else SIZE)
        return self.position

    def read(self, size=-1):
        size = min(SIZE - self.position, size if size >= 0 else SIZE)
        if size <= 0:
            return b""
        data = fetch(self.position, self.position + size - 1)
        self.position += len(data)
        return data


if __name__ == "__main__":
    with zipfile.ZipFile(RemoteZip()) as archive:
        name = next(n for n in archive.namelist() if n.endswith("/windows_release_x86_64.exe"))
        content = archive.read(name)  # zipfile verifies the entry's CRC before returning.
    assert content[:2] == b"MZ", "Expected a Windows executable"
    target = ROOT / "tools/windows_release_x86_64.exe"
    target.write_bytes(content)
    print(f"Downloaded {target.name}: {len(content):,} bytes")
