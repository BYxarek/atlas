# Changelog

## Unreleased

## 0.3.0 — 2026-11-08

- Set the Android version code to 14 and update the mod SDK, browser editor and examples for game version 0.3.0.
- Restrict phone orientation to landscape in both horizontal directions.
- Add a persistent FPS counter and public lobby diagnostics showing server round-trip time, recent probe/request failures and each connected player's ping. Show raw packet loss as unavailable on WebSocket and HTTPS.
- Add natural satellite land colors, mapped rivers and lakes, and 3D forest patches based on MODIS land cover in the Earth 2.5D view. Keep political control visible as a translucent tint.
- Render 2.5D terrain from NOAA ETOPO elevation and bathymetry. Drape country colors, borders and hatched battle fronts on the relief and align picking to the surface. Add 3D infantry, aircraft and ships on close zoom, animated water, combat and movement effects, and an optional desktop quality setting for shadows and antialiasing.
- Add an optional 2.5D map view with a tilted orthographic camera, raised coastlines and shaded troop markers. Preserve country selection, zoom and battle fronts in both views.
- Animate advancing armies and a moving front within contested territories. Conquests settle into the new map color, while repelled armies retreat and their temporary front recedes.
- Validate Windows release gameplay/save UI and Android API 37 emulator gameplay, rotation, background/resume and native mod import. Add exported-PCK smoke checks for vanilla and portable mod rules/UI/save-load.
- Make build/test runners reject Godot engine errors even with exit code zero; exclude generated build artifacts from Godot imports and stop test audio before teardown to prevent leaked resources.
- Extend the mod workbench with typed content/scenario/victory forms, block events, editable map vertices/islands/countries, media/theme/research previews, path-based errors and warnings, autosaved source projects, bounded undo/redo and lossless opaque API 2 PCK roundtrips. Add version/save compatibility reports.
- Add one shared AI policy schema and implementations for technology/building/recruitment priorities, target selection and attack retreat. Fix bot event timestamps to keep Godot/PHP deterministic.
- Add actual seeded mod balance batches, comparable non-overwriting reports, exact-version .atlaspack bundles and lock files, dependency ordering, staged verified extraction and in-game network set installation. Extend SDK/site documentation and regression checks.

- Add portable mod API 2: partial balance patches with source/conflict inspection, extra troop branches, buildings, dependency-based research, replacement maps, scenarios, alliances and custom victory conditions. Use the same validated content and deterministic event rules in solo/LAN/VPS/PHP; bump LAN/VPS wire to 11 and PHP protocol to 5.
- Add bounded declarative events with persistent flags/research/RNG, data-only PNG flags/WAV cues, RU/EN translations, theme colors and text/action panels. Preserve exact-profile saves; include portable JSON changes in solo approval/save fingerprints.
- Add bilingual browser mod studio with balance/scenario/content editors, JSON/package import/export and single-file .atlasmod assembly; extend standalone SDK, full API reference and Frontier example. Add in-game tools for rules, package/save validation and isolated test campaigns, CLI validation/inspection and cross-transport/content parity checks.

- Add bilingual on-site mod documentation with all balance parameters, examples, standalone SDK downloads and hosting/recovery guidance for the development build.

- Package mods as single .atlasmod files. Add one shared network-mod schema and separate folder for LAN/VPS/PHP, consent-based chunked downloads, exact-profile admission, restart/reconnect and isolated server saves. Add cross-transport package tests; bump LAN/VPS to wire 10 and PHP to protocol 4.

- Add trusted native PCK mods: early bootstrap loading, installation and load-order UI, dependency/conflict/version checks, SHA-256 approval, recovery mode, isolated campaign saves and multiplayer guard. Include authoring tools, a balance mod example and mod regression checks.

- Expand the atlas from 176 to 244 countries/territories with 68 small-state/island additions, selectable markers, reciprocal borders and 42 dependency links; preserve existing IDs.
- Hide five enclosed microstates until a surrounding country is conquered: each rolls a 50% peaceful accession or declaration of war once, persisted in solo/LAN/VPS/PHP saves. Peaceful accession grants no conquest or nuclear rewards.
- Offer 239 starting countries/seats; keep island microstates separate. Expand legacy 176-country saves and update LAN/VPS wire protocol to 9 and PHP protocol to 3.

- Brighten the ocean, player territories and selection outlines; keep unscouted foreign countries gray and reveal political-group colors after reconnaissance.
- Refresh shared desktop/mobile menus, buttons, panels and text with richer blue, turquoise and gold colors and clearer hover/focus states.

## 0.2.0 — 2026-11-05

- Publish a source-only GitHub release; local EXE/APK builds and archives are not attached. Android version code is 13.
- Add persistent battle reports for attackers and defenders: strength, technology, naval penalty, rebels and losses, available in notifications and the journal.
- Assign bot strategies and preferences randomly per session; preserve them and random state through saves and reconnects.
- Share economic and combat parameters through assets/balance.json; generate and verify the PHP copy.
- Extend Godot/PHP parity to three seeded 15-minute bot sessions with save/resume and precise field diagnostics.
- Add automated balance simulations, concurrent PHP storage benchmarks and opt-in private numeric metrics.
- Make UI assertions respect the selected locale, including English GitHub Actions runners.
- Print PHP integration logs as UTF-8 so Cyrillic output does not fail Windows CI with a legacy console encoding.
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
