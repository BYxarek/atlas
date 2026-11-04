# ATLAS — World Domination

English | [Русский](README.ru.md)

An open-source native 2D world-conquest strategy game for **Windows and Android**, built with Godot 4.7.2. Choose a country, grow an economy, upgrade your army, gather intelligence and conquer the map. Play solo or against friends and bots on servers you control.

**Version: 0.1.0 — first public release.** This is an early release; Android hardware validation is still pending.

[Project presentation](https://byxarek.github.io/atlas/) · [Game mechanics](docs/MECHANICS.md) · [Documentation index](docs/README.md)

## Download and play

Get the files from [GitHub Releases](https://github.com/BYxarek/atlas/releases/latest):

| File | Purpose |
| --- | --- |
| `Atlas-Windows-x64.zip` | Extract and run `Atlas.exe` on Windows x64 |
| `Atlas-Android.apk` | Signed native APK for Android 7.0+, OpenGL ES 3.0 |
| `Atlas-VPS-Source.zip` | Self-hosted Linux x64 server with Docker Compose and automatic HTTPS |
| `Atlas-PHP-Hosting.zip` | Server for shared hosting with PHP 8.1+, HTTPS and cron |
| `SHA256SUMS.txt` | Checksums for the release downloads |

Android includes armeabi-v7a, arm64-v8a, x86 and x86_64 libraries. Install updates over the existing app to retain local data. Neither client needs Godot installed. Russian and English are available in **Settings → Language**.

## Features

- A full-window world map with 176 territories, country colors and animated operations.
- Infantry, aircraft and naval recruitment and technology upgrades.
- One to five businesses per country; each level produces one coin per second.
- Spies, reconnaissance reports and uncertain attack warnings 60–300 game seconds in advance.
- Enemy invasions, defense and nuclear strikes earned through conquest.
- Separate campaigns, manual snapshots, autosaves and backup files.
- Sound effects, notification animations, statistics and an event journal.
- Touch controls, pinch zoom, portrait/landscape layouts and Android Back handling.
- Multiplayer lobbies with readiness, bots, reconnecting and player management; up to eight player/bot slots.
- LAN hosting, authoritative VPS WebSocket servers and authoritative PHP/HTTPS servers. Windows and Android use the same protocols.

Every selected starting country receives the same army and treasury: 35 infantry, 8 aircraft, 4 ships and 180 coins. Neutral-country strength uses game-specific values calibrated to the Global Firepower 2026 ordering, not real troop counts. In solo play your last country is protected from invasions; PvP can eliminate a player.

## Documentation

- [Installation and controls](docs/PLAYING.md)
- [Game mechanics and balance](docs/MECHANICS.md) · [Русский](docs/MECHANICS.ru.md)
- [GitHub Pages maintenance](docs/PAGES.md)
- [Build from source and run checks](docs/BUILDING.md)
- [Multiplayer, profiles and saves](docs/MULTIPLAYER.md)
- [Android setup and signing](docs/ANDROID.md) · [Русский](ANDROID.md)
- [VPS deployment](server/README.en.md) · [Русский](server/README.md)
- [PHP shared hosting deployment](hosting/README.en.md) · [Русский](hosting/README.md)
- [Contributing](CONTRIBUTING.md), [release procedure](docs/RELEASING.md), [changelog](CHANGELOG.md)

## Development

Open `project.godot` in Godot **4.7.2** and run the project. The code is GDScript, with PHP for the shared-hosting backend. On Windows the complete checked build is:

```powershell
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

See the build guide for Python, Android SDK/JDK and export-template requirements. Generated binaries, signing keys and server data are excluded from Git.

## License and credits

Project code is available under the [MIT License](LICENSE). Third-party components and assets retain their own terms: [credits and notices](LICENSES.md). Map data is Natural Earth public domain; included sounds are CC0; Godot uses MIT. The game is not affiliated with Global Firepower.
