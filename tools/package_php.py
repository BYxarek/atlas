"""Build an FTP upload bundle without local config, saves or credentials."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root=Path(__file__).resolve().parent.parent
names=['mod_rules.php','mod_runtime.php','mod_catalog.php','mods.php','api.php','service.php','simulation.php','cron.php','storage.php','index.php','config.example.php','data.json','balance.json','.htaccess','README.md','README.en.md']
assert (root/'assets/balance.json').read_bytes()==(root/'hosting/balance.json').read_bytes(), 'Run tools/prepare_php.gd before packaging'
output=root/'build/Atlas-PHP-Hosting.zip'
output.parent.mkdir(exist_ok=True)
with ZipFile(output,'w',ZIP_DEFLATED) as archive:
    archive.writestr('network_mods/', '')
    for name in names:archive.write(root/'hosting'/name,name)
    archive.write(root/'LICENSE','LICENSE')
print('Ready:',output)
