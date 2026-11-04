# Contributing

Use issues for reproducible bugs and feature proposals, and pull requests for changes. Include platform, game version, steps to reproduce and relevant logs. Remove profile keys, server addresses you do not want public, passwords and save data before posting.

Use Godot 4.8-beta2 and keep model rules independent of interface language. UI text belongs in `src/i18n.gd` / `assets/i18n/en.json`; run `python tools/check_translations.py` after changing visible text. Update both English and Russian documentation when behavior changes.

Run checks appropriate to your change; game rules need the corresponding Godot and PHP parity checks. Network changes should exercise reconnects and saves, and mobile UI changes should be checked in portrait and landscape. See [build instructions](docs/BUILDING.md).

Never commit signing keys, `export_credentials.cfg`, server `.env`, `hosting/config.php`, room data or generated builds. Contributions are submitted under the project's MIT License; third-party assets need compatible license notices.
