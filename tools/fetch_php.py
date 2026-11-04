"""Locate PHP for tests; download the verified portable Windows CLI when needed."""
from pathlib import Path
import hashlib
import os
import shutil
import urllib.request
import urllib.error
import zipfile

def php_binary():
    installed=shutil.which('php')
    if installed:return Path(installed)
    root=Path(__file__).resolve().parent
    executable=root/'php/php.exe'
    if executable.exists():return executable
    if os.name!='nt':raise RuntimeError('Install PHP 8.1+ CLI to run PHP hosting checks')
    name='php-8.4.27-1-nts-Win32-vs17-x64.zip'
    archive=root/'php.zip'
    try:urllib.request.urlretrieve('https://windows.php.net/downloads/releases/'+name,archive)
    except urllib.error.HTTPError as error:
        if error.code!=404:raise
        urllib.request.urlretrieve('https://windows.php.net/downloads/releases/archives/'+name,archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!='dbae154a0a89791f36c3d48e68bae797878333e7d6cb5721e74617de59b63ab7':
        raise RuntimeError('PHP download checksum mismatch')
    with zipfile.ZipFile(archive) as bundle:bundle.extractall(root/'php')
    return executable
