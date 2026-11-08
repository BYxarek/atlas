"""Package only the source files needed to build the self-hosted VPS image."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parent.parent
files = [root / name for name in (
    "project.godot", "main.tscn", "bootstrap.tscn", "export_presets.cfg", "LICENSES.md", "LICENSE", ".dockerignore",
    "assets/world.json", "assets/military.json", "assets/balance.json", "assets/icon.svg", "assets/boot_splash.png",
    "assets/i18n/en.json",
    "assets/legal/GODOT-LICENSE.txt", "assets/legal/GODOT-COPYRIGHT.txt", "assets/legal/LICENSES.md",
    "tools/GODOT-LICENSE.txt", "tools/GODOT-COPYRIGHT.txt",
)]
files += list((root / "src").glob("*.gd"))
files += [root / "server" / name for name in (
    "Dockerfile", "compose.yaml", "Caddyfile", ".env.example", "entrypoint.py", "README.md", "README.en.md",
)]
output = root / "build/Atlas-VPS-Source.zip"
output.parent.mkdir(exist_ok=True)
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for file in files:
        archive.write(file, file.relative_to(root).as_posix())
print(f"Ready: {output}")
