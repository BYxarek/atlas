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

## Windows MSI installer

Use [WiX Toolset 7.0.1](https://github.com/wixtoolset/wix/releases/tag/v7.0.1) to package the Windows x64 export. Use a freshly extracted `Atlas-Windows-x64.zip` for an existing release, or the staging directory from a fresh local build. Set the MSI version to match the game export. Run these commands from the repository root after reviewing the [WiX EULA](https://docs.firegiant.com/wix/osmf/).

```powershell
$payload = (Resolve-Path 'build/windows-v0.3.0').Path
wix extension add -g -acceptEula wix7 WixToolset.UI.wixext/7.0.1
wix build -acceptEula wix7 -arch x64 -ext WixToolset.UI.wixext/7.0.1 -culture en-US -loc tools/AtlasUI.wxl -bindpath "$payload" -bindpath "Payload=$payload" -define Version=0.3.0 -pdbtype none -o build/Atlas-Windows-x64.msi tools/Atlas.wxs tools/AtlasUI.wxs
wix msi validate -acceptEula wix7 -sice ICE57 build/Atlas-Windows-x64.msi
```

The validation command skips ICE57 because Windows redirects both the shortcut folders and their registry key paths to the selected install scope. Expect an ICE61 warning about allowing replacement of the original MSI with the same game version.

Open `Atlas-Windows-x64.msi` and choose English or Russian. On the installation screen, select the folder and the shortcuts you want. By default, the MSI installs for the current user and creates a Start menu shortcut. The desktop shortcut is optional. To open ATLAS immediately, select **Launch the game** on the final screen and click **Finish**.

To upgrade, close the game and run the newer MSI under the same Windows account. The wizard reuses the installation folder and the shortcut choices recorded by the previous package. The current MSI can also replace earlier installer builds of 0.3.0. Saves and mods live in `%APPDATA%\AtlasWorldGame` outside the installation folder. Windows Settings can uninstall the game.

Open the MSI for the installed build again and choose a language to access the standard maintenance wizard. **Repair** restores game files and selected shortcuts in the existing folder. **Remove** uninstalls the game and its shortcuts. Both actions preserve saves and mods.

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
