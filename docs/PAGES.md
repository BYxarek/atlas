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
