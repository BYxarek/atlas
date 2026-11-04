"""Every Russian source string must have an English catalog entry."""
from pathlib import Path
import ast
import json
import re

root=Path(__file__).resolve().parent.parent
catalog=json.loads((root/'assets/i18n/en.json').read_text(encoding='utf-8'))
missing=[]
for file in (root/'src').glob('*.gd'):
    for match in re.finditer(r'"(?:\\.|[^"\\])*"',file.read_text(encoding='utf-8')):
        value=ast.literal_eval(match.group())
        if re.search('[\u0400-\u04ff]',value) and value not in catalog:missing.append((file.name,value))
if missing:
    for file,value in missing:print('MISSING:',file,repr(value))
    raise SystemExit(1)
print('PASS:',len(catalog),'translation entries; all source strings covered')
