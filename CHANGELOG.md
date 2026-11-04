# Changelog

## 0.2.0 — 2026-11-05

- Publish a source-only GitHub release; local EXE/APK builds and archives are not attached. Android version code is 13.
- Add persistent battle reports for attackers and defenders: strength, technology, naval penalty, rebels and losses, available in notifications and the journal.
- Assign bot strategies and preferences randomly per session; preserve them and random state through saves and reconnects.
- Share economic and combat parameters through assets/balance.json; generate and verify the PHP copy.
- Extend Godot/PHP parity to three seeded 15-minute bot sessions with save/resume and precise field diagnostics.
- Add automated balance simulations, concurrent PHP storage benchmarks and opt-in private numeric metrics.
- Make UI assertions respect the selected locale, including English GitHub Actions runners.
- Add CLI backup/restore with rollback checks, a checks-only build and GitHub Actions game checks; include war-rule tests.
- Bump LAN/VPS wire protocol to 8 and PHP protocol to 2; update client and server together. Existing saves without new optional fields remain readable.
- Validate Android with the API 37 Android Studio emulator; replace oversized mobile confirmation/message windows with responsive in-scene dialogs.

## 0.1.1 — 2026-11-04

- Migrate Windows, Android and the shared server build to verified Godot 4.8-beta2 editor/export templates.
- Use native theme UI sounds with the existing volume controls, fuzzy country search in both lists, and automatic country-panel heading font sizing.
- Retain mobile transitions; preserve save formats, network protocols, Android signing identity and application ID.
- Android version code is 12. This build uses a prerelease engine; physical Android validation is pending.
- Review notes cover 4.8 dev1–dev7, beta1 and beta2.


## 0.1.0 — 2026-11-04

First public release. Earlier 0.x numbers belonged to local development builds.

- Native Windows x64 and signed Android clients.
- Russian and English interface, country names, notifications and event history.
- Mobile touch controls and portrait/landscape layouts.
- World conquest, businesses, troop recruitment/research, spies, invasions and nuclear strikes.
- Autosaves, manual snapshots, sound effects and animated notifications.
- PvP/bot lobbies, LAN discovery and reconnect support.
- Self-hosted authoritative VPS/WebSocket and PHP/HTTPS backends.
- English project documentation and Russian guides.

- Universal Android APK: armeabi-v7a, arm64-v8a, x86 and x86_64, with required engine-library verification.
- Bilingual GitHub Pages presentation and mechanics guides.

Android `versionCode` is 11 to preserve upgrades from local development APKs. Wire protocol versions and save schemas are unchanged. Physical Android hardware testing remains pending.
