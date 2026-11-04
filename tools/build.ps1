param([switch]$ChecksOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$version = (Get-Content (Join-Path $PSScriptRoot 'godot_release.json') -Raw | ConvertFrom-Json).version
$editorPath = Join-Path $PSScriptRoot "godot-$version/Godot_v${version}_win64_console.exe"
python tools/fetch_windows_template.py
if ($LASTEXITCODE -ne 0) { throw 'Godot editor/template verification failed' }

& $editorPath --headless --path $projectRoot --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
python tools/check_translations.py
if ($LASTEXITCODE -ne 0) { throw 'Translation coverage check failed' }
python tests/test_storage_tools.py
if ($LASTEXITCODE -ne 0) { throw 'Storage tools checks failed' }
python tests/test_build_tools.py
if ($LASTEXITCODE -ne 0) { throw 'Godot installer checks failed' }
python tests/test_check_runner.py
if ($LASTEXITCODE -ne 0) { throw 'Test runner checks failed' }
foreach ($testScript in @('tests/test_game.gd', 'tests/test_features.gd', 'tests/test_warnings.gd', 'tests/test_military.gd', 'tests/test_audio.gd', 'tests/test_ui.gd', 'tests/test_network.gd', 'tests/test_mobile.gd', 'tests/test_mobile_layout.gd', 'tests/test_war_rules.gd', 'tests/test_strategy.gd')) {
    python tools/test_godot.py $testScript
    if ($LASTEXITCODE -ne 0) { throw "Tests failed: $testScript" }
}

python tools/test_network.py
if ($LASTEXITCODE -ne 0) { throw 'Network transport checks failed' }
New-Item -ItemType Directory -Path 'build/vps' -Force | Out-Null
& $editorPath --headless --path $projectRoot --export-pack 'VPS Server' 'build/vps/AtlasServer.pck'
if ($LASTEXITCODE -ne 0) { throw 'VPS pack export failed' }
python tools/test_vps.py --server-pack build/vps/AtlasServer.pck
if ($LASTEXITCODE -ne 0) { throw 'Dedicated server checks failed' }
& $editorPath --headless --path $projectRoot --script tools/prepare_php.gd
if ($LASTEXITCODE -ne 0) { throw 'PHP map preparation failed' }
python tools/test_php.py
if ($LASTEXITCODE -ne 0) { throw 'PHP hosting checks failed' }
if ($ChecksOnly) { Write-Host 'All checks passed'; return }

$outputDirectory = Join-Path $projectRoot 'build/windows-v0.2.0'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
& $editorPath --headless --path $projectRoot --export-release 'Windows Desktop' (Join-Path $outputDirectory 'Atlas.exe')
if ($LASTEXITCODE -ne 0) { throw 'Windows export failed' }
Copy-Item -LiteralPath README.md,README.ru.md,ANDROID.md,LICENSE,LICENSES.md,tools/GODOT-LICENSE.txt,tools/GODOT-COPYRIGHT.txt -Destination $outputDirectory -Force
Copy-Item -Path docs -Destination $outputDirectory -Recurse -Force
Copy-Item -LiteralPath hosting/README.md -Destination (Join-Path $outputDirectory 'PHP-Hosting-README.md') -Force
$audioLicenses = Join-Path $outputDirectory 'Audio-Licenses'
New-Item -ItemType Directory -Path $audioLicenses -Force | Out-Null
Copy-Item -Path 'assets/audio/licenses/*' -Destination $audioLicenses -Force
Copy-Item -LiteralPath 'assets/audio/manifest.json' -Destination (Join-Path $audioLicenses 'audio-manifest.json') -Force
Compress-Archive -Path "$outputDirectory/*" -DestinationPath 'build/Atlas-Windows-x64.zip' -Force
python tools/package_vps.py
if ($LASTEXITCODE -ne 0) { throw 'VPS source packaging failed' }
python tools/package_php.py
if ($LASTEXITCODE -ne 0) { throw 'PHP hosting packaging failed' }
python tools/build_android.py
if ($LASTEXITCODE -ne 0) { throw 'Android export failed' }
Write-Host "Ready: $outputDirectory/Atlas.exe"
