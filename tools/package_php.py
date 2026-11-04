"""Build an FTP upload bundle without local config, saves or credentials."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root=Path(__file__).resolve().parent.parent
names=['api.php','service.php','simulation.php','cron.php','index.php','config.example.php','data.json','.htaccess','README.md','README.en.md']
output=root/'build/Atlas-PHP-Hosting.zip'
output.parent.mkdir(exist_ok=True)
with ZipFile(output,'w',ZIP_DEFLATED) as archive:
    for name in names:archive.write(root/'hosting'/name,name)
    archive.write(root/'LICENSE','LICENSE')
print('Ready:',output)
