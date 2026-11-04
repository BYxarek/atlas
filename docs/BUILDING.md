# Build from source

[Documentation index](README.md)

## Requirements

- Godot 4.7.2 standard edition (not .NET).
- Python 3.10+ and PowerShell for the supplied full Windows build.
- For Android: Android SDK with platform-tools, build-tools (35.0.1 or newer) and JDK 17+. Android Studio's JBR is supported.
- PHP 8.1+ CLI for backend tests; the Windows test helper can download a checksum-verified portable PHP.

Clone the repository and open `project.godot` in Godot to edit or play. Generated map, balance and audio assets are already included.

```powershell
git clone https://github.com/BYxarek/atlas.git
cd atlas
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

The script downloads the pinned Windows editor and export template if absent, imports assets, checks translation coverage, runs game/UI/mobile/network/VPS/PHP tests and exports Windows, server bundles and Android. An internet connection is needed for missing tools. The Android step requires a configured SDK and JDK; see [Android](ANDROID.md). Native scripts are currently oriented toward a Windows build host.

Outputs are under `build`: `windows-v0.1.0/Atlas.exe`, `Atlas-Windows-x64.zip`, `Atlas-Android.apk`, `Atlas-VPS-Source.zip` and `Atlas-PHP-Hosting.zip`.

## Focused checks

```powershell
python tools/check_translations.py
& tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/test_game.gd
& tools/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tests/test_mobile.gd
python tools/test_network.py
python tools/test_vps.py
python tools/test_php.py
```

The mobile tests exercise responsive layouts, touch and localization in native desktop Godot. They do not replace Android hardware testing. Docker deployment/TLS provisioning on a real VPS and hosting-provider load limits require separate environment tests.
