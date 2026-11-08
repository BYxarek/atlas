# Build from source

[Documentation index](README.md)

## Requirements

- Godot 4.8-beta2 standard edition (not .NET).
- Python 3.10+ and PowerShell for the supplied full Windows build.
- For Android: Android SDK with platform-tools, build-tools 36.1.0 and JDK 17+. Android Studio's JBR is supported. Install the required build tools with `android sdk install build-tools/36.1.0`.
- PHP 8.1+ CLI for backend tests; the Windows test helper can download a checksum-verified portable PHP.

Clone the repository and open `project.godot` in Godot to edit or play. Generated map, balance and audio assets are already included.

```powershell
git clone https://github.com/BYxarek/atlas.git
cd atlas
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

The script downloads the pinned Windows editor and export template if absent, imports assets, checks translation coverage, runs game/UI/mobile/network/VPS/PHP tests and exports Windows, server bundles and Android. An internet connection is needed for missing tools. The Android step requires a configured SDK and JDK; see [Android](ANDROID.md). Native scripts are currently oriented toward a Windows build host.

Outputs are under `build`: `windows-v0.3.0/Atlas.exe`, `Atlas-Windows-x64.zip`, `Atlas-Android.apk`, `Atlas-VPS-Source.zip` and `Atlas-PHP-Hosting.zip`.

## Focused checks

```powershell
python tools/check_translations.py
& tools/godot-4.8-beta2/Godot_v4.8-beta2_win64_console.exe --headless --path . --script tests/test_game.gd
& tools/godot-4.8-beta2/Godot_v4.8-beta2_win64_console.exe --headless --path . --script tests/test_mobile.gd
python tools/test_network.py
python tools/test_vps.py
python tools/test_php.py
```

The mobile tests exercise responsive layouts, touch and localization in native desktop Godot. They do not replace Android hardware testing. Docker deployment/TLS provisioning on a real VPS and hosting-provider load limits require separate environment tests.

Use `./tools/build.ps1 -ChecksOnly` to run the complete check stage without client exports. The Game checks workflow runs this stage on Windows for pull requests and main. See [balance, storage diagnostics and rollback](TECHNICAL_IMPROVEMENTS.ru.md).
