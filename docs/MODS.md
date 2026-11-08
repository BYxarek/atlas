# ATLAS mods

[Полное руководство на русском](MODS.ru.md)

Mods ship as a single **`.atlasmod`** file. Use **Mods → Install mod…** for solo play, or **Install network mod…** to copy the same file into the separate `user://network_mods/` folder. There are no transport-specific mod variants: LAN, VPS and PHP consume the same packages and shared `network_balance` schema.

Solo mods can replace data, graphics, audio, scenes and gameplay scripts and execute with the game's permissions. They require explicit enablement and a restart. Network API 2 supports validated balance patches, extra troops/buildings/research, maps/scenarios/alliances/objectives, declarative events and data-only media/UI. Native PCK code is ignored in network play on all transports. See the complete [API 2 reference and editor](https://byxarek.github.io/atlas/mods.html#api2).

When joining a room with another profile, the game offers all required names, versions and sizes before allocating a seat. With consent, missing packages are downloaded from that host into `network_mods/cache/`, checked against exact sizes and SHA-256, and activated after restart. Existing exact copies are reused. Desktop clients can restart and reconnect; Android/editor users close and reopen the game with the saved profile/target. Entering a vanilla room similarly offers to disable the active network set.

LAN hosts use **Launch with network mods**, restart and create a lobby. VPS operators put the same files into `ATLAS_MODS_DIR` (default `user://network_mods`, Docker `/data/network_mods`). PHP operators use `network_mods/` beside `api.php` and deploy `mod_catalog.php` and `mods.php` with the updated service/simulation. No ZIP extension is needed. One server process uses one fixed ordered profile for all its rooms; files in the folder root define the host set (downloaded files stay in `cache/`); filename order determines precedence, so prefix dependencies first. Update files only while the server is stopped. Current protocols: LAN/VPS **11**, PHP **5**.

Build the shared 1000-starting-coins example:

```powershell
& tools/godot-4.8-beta2/Godot_v4.8-beta2_win64_console.exe --headless --path . --script tools/build_mod.gd -- examples/starter-economy build/mods/starter-economy.atlasmod
```

The output must be new. Sources contain `mod.json` plus `files/` preserving game resource paths, or an already-exported `content.pck`. Required manifest fields: `api` (1 or 2), `id`, `name`, `version`, `game_version` (exactly `0.3.0`). Optional: `description`, `requires`, `conflicts`, `network_balance`. IDs use 1–64 lowercase ASCII letters, digits, `_`, `-`. For a source containing only `files/assets/balance.json`, the builder automatically includes common network rules, so that single output works unchanged in all network modes.

The container is 8 ASCII bytes `ATLASMOD`, a little-endian uint32 JSON length, UTF-8 manifest with `pck_sha256`, then the PCK. Limit: 64 MiB per file, 32 mods and 128 MiB per profile, 4 MiB manifest. Transfers use bounded 64 KiB chunks, timeouts, hash-based cache paths, no third-party URLs and no HTTP redirects. Solo and network profiles/saves are separate. Recover with `Atlas.exe -- --no-mods`; return to solo mods from the manager or rename `user://network_boot.json` to clear a network profile.

Tests: `tests/test_mod_package.gd`, `tests/test_mods.gd`, `python tools/test_network_mods.py`. The integration test transfers the same package through every transport, reconnects in another process and verifies the same simulation rules. See the Russian guide for detailed authoring and recovery instructions.

API 2 sources can contain only mod.json (no files/). See examples/frontier/mod.json. Validate the ordered profile with tools/mod_tool.gd (validate, inspect, save-check); extra dependency packages can follow OUTPUT in build_mod.gd. In-game Mods → Mod tools opens the inspector, package/save checker and a separate test campaign. Changed profiles do not migrate saves automatically.
