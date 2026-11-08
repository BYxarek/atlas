"""Generate the bilingual portable mod editor and reference from shipped examples."""
import base64
import json
import hashlib
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'website'


def main():
    frontier = json.loads((ROOT/'examples/frontier/mod.json').read_text(encoding='utf-8'))
    patch = {k: frontier[k] for k in ('api', 'id', 'name', 'version', 'game_version')}
    patch.update(id='my-mod', name='My mod', changes={'start_coins': 500}, content={})
    data = dict(balance=json.loads((ROOT/'assets/balance.json').read_text()),
                atlas=json.loads((ROOT/'assets/world.json').read_text(encoding='utf-8')),
                empty_pck=base64.b64encode((SITE/'examples/empty.pck').read_bytes()).decode(),
                templates={'patch': patch, 'frontier': frontier})
    (SITE/'mod-studio-data.json').write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
    payload=(SITE/'examples/empty.pck').read_bytes()
    manifest=json.dumps(frontier|{'pck_sha256':hashlib.sha256(payload).hexdigest()},ensure_ascii=False).encode('utf-8')
    (SITE/'examples/frontier.atlasmod').write_bytes(b'ATLASMOD'+struct.pack('<I',len(manifest))+manifest+payload)
    for ru in (True, False):
        t = lambda a, b: a if ru else b
        title = t('Редактор модов', 'Mod editor')
        html = f'''<!doctype html><html lang="{t('ru','en')}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} — ATLAS</title><link rel="icon" href="assets/icon.svg"><link rel="stylesheet" href="style.css"><link rel="stylesheet" href="mod-docs.css"><link rel="stylesheet" href="mod-studio.css"><script src="mod-studio-core.js" defer></script><script src="mod-studio.js" defer></script><script src="mod-studio-workbench.js" defer></script></head><body class="documentation"><header class="wrap"><a class="brand" href="{t('ru.html','index.html')}">ATLAS / MOD API 2</a><nav><a href="{t('mods.ru.html','mods.html')}">{t('Документация','Documentation')}</a><a href="{t('mod-studio.html','mod-studio.ru.html')}">{t('EN','RU')}</a></nav></header><main class="wrap"><h1>{title}</h1><p>{t('Редактируйте баланс, стартовые территории и контент. Файлы обрабатываются в браузере. Экспорт — один .atlasmod для LAN, VPS и PHP.', 'Edit balance, starting territories and content. Files stay in your browser. Export one .atlasmod for LAN, VPS and PHP.')}</p><p class="notice">{t('Для разрабатываемой сборки игры. Проверка здесь предварительная: перед выпуском выполните mod_tool.gd validate для всего набора. Сетевой сервер использует один общий профиль модов.', 'For the development game build. Browser checks are preliminary: run mod_tool.gd validate on the full profile before publishing. A network server uses one shared mod profile.')}</p><p>{t('Чтобы изменить подписи нового меню, добавьте точные ключи в content.translations в полном манифесте. Цвета текста и акцента задаются в content.theme.', 'To customize the new menu labels, add exact keys to content.translations in the full manifest. Set text and accent colors in content.theme.')} <a href="{t('mods.ru.html','mods.html')}#api2">{t('Справочник API 2','API 2 reference')}</a></p><p id="status" role="status" aria-live="polite">Loading…</p><div class="toolbar"><label>{t('Шаблон','Template')} <select id="template"><option value="patch">Balance patch</option><option value="frontier">Frontier — full example</option></select></label><button id="load-template">{t('Загрузить шаблон','Load template')}</button><label>{t('Импорт JSON / .atlasmod','Import JSON / .atlasmod')} <input id="import" type="file" accept=".json,.atlasmod"></label><button id="check">{t('Проверить','Check')}</button><button id="export-json">JSON ↓</button><button id="export-mod">.atlasmod ↓</button></div><div class="studio-grid"><section><h2>{t('Баланс','Balance')}</h2><div id="balance-fields"></div><h2>{t('Сценарий и карта','Scenario and map')}</h2><label>{t('Страна','Country')} <select id="country"></select></label><svg id="scenario-map" viewBox="-180 -90 360 180" aria-label="World map"></svg><label>{t('Монеты','Coins')} <input id="country-coins" type="number" min="0" max="100000000" value="500"></label><label>{t('Дополнительные владения (ID через запятую)','Additional territories (comma-separated IDs)')} <input id="country-owned" placeholder="2, 3"></label><button id="save-start">{t('Сохранить старт этой страны','Save this country start')}</button><button id="copy-map">{t('Добавить текущую карту в JSON для редактирования','Copy current map into JSON for editing')}</button><h2>{t('Объекты контента','Content entries')}</h2><label>{t('Тип','Type')} <select id="entry-kind"><option>units</option><option>buildings</option><option>technologies</option><option>events</option><option>panels</option></select></label><div id="content-list"></div><label>JSON <textarea id="entry-json" rows="12" spellcheck="false"></textarea></label><button id="save-entry">{t('Добавить / заменить по ID','Add / replace by ID')}</button><h2>{t('Изображения и звук','Images and audio')}</h2><label>{t('Ключ','Key')} <input id="media-key" value="flag:0" placeholder="flag:0 / sound:victory"></label><label>PNG / WAV <input id="add-media" type="file" accept="image/png,audio/wav,.wav"></label><p>{t('До 192 КиБ на ресурс; PNG до 1024×1024. Звук заменяет существующий сигнал игры.', 'Up to 192 KiB per resource; PNG up to 1024×1024. Audio replaces an existing game cue.')}</p></section><section><h2>{t('Полный манифест','Full manifest')}</h2><label>mod.json<textarea id="source" rows="45" spellcheck="false"></textarea></label><button id="apply-json">{t('Применить JSON к редактору','Apply JSON to editor')}</button><p>{t('В JSON доступны геометрия карты, гарнизоны, союзы, условия победы, события, переводы и тема. Пример Frontier содержит рабочие варианты. Для удаления объекта используйте кнопку рядом с ним.', 'JSON exposes map geometry, garrisons, alliances, victory conditions, events, translations and theme. Frontier provides working examples. Use the adjacent button to remove an entry.')}</p><pre id="preview"></pre></section></div></main><footer class="wrap">ATLAS © 2026 BYxarek</footer></body></html>'''
        (SITE/t('mod-studio.ru.html','mod-studio.html')).write_text(html, encoding='utf-8')


if __name__ == '__main__':
    main()
