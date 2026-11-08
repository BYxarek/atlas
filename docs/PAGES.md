# GitHub Pages / Презентация проекта

English: The public presentation lives at <https://byxarek.github.io/atlas/>; Russian is `ru.html`. Static HTML/CSS and screenshots are in `website/`. No build tool, package install or backend is required. GitHub Pages hosts the presentation only; use the VPS or PHP guides to host multiplayer.

Русский: Публичная презентация — <https://byxarek.github.io/atlas/ru.html>. Исходники HTML/CSS и скриншоты находятся в `website/`. Сборщик и зависимости не нужны. GitHub Pages обслуживает презентацию; игровой сервер разворачивается отдельно по инструкциям [VPS](../server/README.md) или [PHP](../hosting/README.md).

## Preview / Предпросмотр

```sh
python -m http.server 8080 --directory website --bind 127.0.0.1
```

Open / откройте `http://127.0.0.1:8080`. Keep both language pages and image descriptions in sync. Обновляйте обе языковые страницы и описания изображений вместе.

## Publish / Публикация

The `Deploy presentation` workflow publishes `website/` after a push to `main`; it can also be started manually in Actions. In repository Settings → Pages, select GitHub Actions as the source. Check the workflow result and the public URL after changes. A previous version can be restored by reverting the website commit and pushing again.

Workflow `Deploy presentation` публикует `website/` после push в `main` и запускается вручную через Actions. В Settings → Pages выберите GitHub Actions. После изменений проверьте успешность workflow и публичный адрес. Для отката отмените коммит страницы и отправьте изменение в `main`.

Based on [GitHub's Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages).


## Mod documentation / Документация модов

The site includes `mods.html` (English) and `mods.ru.html` (Russian), linked from both landing pages. `tools/build_mod_docs.py` generates the full parameter reference from `assets/balance.json`, localized content and the downloadable standalone SDK with three examples. Update source descriptions there rather than editing generated HTML. This reference and the downloadable examples target ATLAS 0.3.0 on main.

```powershell
python tools/build_mod_docs.py
python tests/test_mod_docs.py
node --check website/mod-docs.js
```

`tests/test_mod_docs.py` checks all local site links/anchors and every balance parameter, extracts the downloadable SDK into a temporary directory and builds all three examples with the pinned Godot editor. No game/client export or server deployment is needed for documentation edits. Include `website/examples/` in the Pages artifact so SDK links work.

Генератор создаёт обе языковые страницы и автономный SDK. Проверка не ограничивается наличием ZIP: все три примера собираются из распакованного архива независимо от игрового проекта. При изменении баланса добавьте описание нового ключа в генератор. Обновляйте CSS/JS вместе со страницами; текст и оглавление доступны без JavaScript.
