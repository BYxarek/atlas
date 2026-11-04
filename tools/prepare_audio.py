"""Prepare downloaded CC0 sounds: uv run --python 3.12 --with imageio-ffmpeg python tools/prepare_audio.py."""
import array
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import wave

import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tools/audio_sources"
OUTPUT = ROOT / "assets/audio"
OUTPUT.mkdir(parents=True, exist_ok=True)
LICENSES = OUTPUT / "licenses"
LICENSES.mkdir(exist_ok=True)
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 44100


def decode(path, duration=4.0, offset=0.0):
    result = subprocess.run([FFMPEG, "-v", "error", "-ss", str(offset), "-i", str(SOURCES / path),
                             "-t", str(duration), "-f", "s16le", "-ac", "1", "-ar", str(RATE), "-"],
                            check=True, capture_output=True)
    pcm = array.array("h", result.stdout)
    assert pcm and max(abs(x) for x in pcm) > 0, f"Empty sound: {path}"
    return [x / 32768 for x in pcm]


def mix(*layers):
    length = max(len(samples) + round(delay * RATE) for samples, delay in layers)
    result = [0.0] * length
    for samples, delay in layers:
        offset = round(delay * RATE)
        for index, value in enumerate(samples):
            result[index + offset] += value
    return result


def write(name, samples, originals):
    peak = max(abs(value) for value in samples)
    assert peak > 0
    gain = 0.67 / peak
    fade = min(round(RATE * 0.008), len(samples) // 4)
    pcm = array.array("h")
    for index, value in enumerate(samples):
        envelope = min(1.0, index / fade, (len(samples) - index - 1) / fade)
        pcm.append(round(value * gain * envelope * 32767))
    temporary = SOURCES / (name + "_prepared.wav")
    with wave.open(str(temporary), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    target = OUTPUT / (name + ".ogg")
    subprocess.run([FFMPEG, "-y", "-v", "error", "-i", str(temporary), "-c:a", "libvorbis", "-q:a", "4", str(target)], check=True)
    assert target.stat().st_size > 500
    manifest[name] = {"file": target.name, "seconds": round(len(samples) / RATE, 3), "license": "CC0-1.0",
                      "sources": [{"file": str(path), "sha256": hashlib.sha256((SOURCES / path).read_bytes()).hexdigest()} for path in originals]}


manifest = {}
simple = {
    "click": ("interface/Audio/click_001.ogg", 0.35),
    "select": ("interface/Audio/select_001.ogg", 0.4),
    "open": ("interface/Audio/open_001.ogg", 0.5),
    "cancel": ("interface/Audio/back_001.ogg", 0.5),
    "confirm": ("interface/Audio/confirmation_001.ogg", 0.7),
    "error": ("interface/Audio/error_004.ogg", 0.6),
    "save": ("interface/Audio/confirmation_002.ogg", 0.7),
    "coins": ("rpg/Audio/handleCoins.ogg", 1.1),
    "upgrade": ("interface/Audio/confirmation_003.ogg", 0.8),
    "unlock": ("interface/Audio/pluck_001.ogg", 0.8),
    "warning": ("interface/Audio/question_001.ogg", 0.7),
    "all_clear": ("interface/Audio/close_001.ogg", 0.6),
    "invasion": ("alarm.ogg", 2.5),
    "report": ("interface/Audio/confirmation_004.ogg", 0.8),
    "notification": ("interface/Audio/glass_001.ogg", 0.8),
    "rocket_launch": ("scifi/Audio/thrusterFire_000.ogg", 1.5),
    "rocket_loop": ("scifi/Audio/spaceEngineLow_000.ogg", 1.5),
    "start": ("jingles/Audio/Pizzicato jingles/jingles_PIZZI00.ogg", 2.5),
    "victory": ("jingles/Audio/Pizzicato jingles/jingles_PIZZI09.ogg", 2.5),
    "defeat": ("jingles/Audio/Pizzicato jingles/jingles_PIZZI10.ogg", 2.5),
    "campaign_win": ("jingles/Audio/Steel jingles/jingles_STEEL16.ogg", 4.0),
    "campaign_lose": ("jingles/Audio/Steel jingles/jingles_STEEL10.ogg", 3.0),
    "spy_send": ("radio.wav", 0.35),
    "spy_loop": ("radio.wav", 1.5),
}
for name, (path, seconds) in simple.items():
    write(name, decode(path, seconds), [path])

naval = "naval/qubodup-NavalBattleSoundSet-cc0/ogg/"
path = naval + "BattleShipMovementAmbient.ogg"
write("naval_loop", decode(path, 3.0), [path])
path = "rpg/Audio/footstep00.ogg"
step = decode(path, 0.35)
march = mix(*[(step, delay) for delay in [0, 0.42, 0.84, 1.26]])
write("army_loop", march, [path])
write("march", march[:round(RATE * 0.8)], [path])
path = naval + "Splash.ogg"
write("march_naval", decode(path, 1.1), [path])
paths = [naval + "GunShotGverb.ogg", naval + "ExplosionMetal.ogg"]
write("battle", mix((decode(paths[0], 1.8), 0), (decode(paths[1], 1.6), 0.16)), paths)
paths = [naval + "WaterSurfaceExplosion01.ogg", naval + "GunShot.ogg"]
write("battle_naval", mix((decode(paths[0], 2.2), 0), (decode(paths[1], 1.8), 0.12)), paths)
paths = ["explosion.ogg", "scifi/Audio/lowFrequency_explosion_000.ogg"]
write("nuke", mix((decode(paths[0], 4), 0.05), (decode(paths[1], 4), 0)), paths)

credits = [
    ("interface", "Kenney", "https://kenney.nl/assets/interface-sounds"),
    ("rpg", "Kenney", "https://kenney.nl/assets/rpg-audio"),
    ("scifi", "Kenney", "https://kenney.nl/assets/sci-fi-sounds"),
    ("jingles", "Kenney", "https://kenney.nl/assets/music-jingles"),
    ("naval", "Iwan Gabovitch / qubodup", "https://opengameart.org/content/tiny-naval-battle-sounds-set"),
    ("explosion", "EZduzziteh", "https://opengameart.org/content/explosions-4"),
    ("alarm", "yd", "https://opengameart.org/content/short-alarm"),
    ("radio", "bretbernhoft", "https://opengameart.org/content/frequency-static-sound-effects"),
]
for pack in ["interface", "rpg", "scifi", "jingles"]:
    shutil.copyfile(SOURCES / pack / "License.txt", LICENSES / (pack + ".txt"))
shutil.copyfile(SOURCES / "naval/qubodup-NavalBattleSoundSet-cc0/README.txt", LICENSES / "naval.txt")
(LICENSES / "sources.txt").write_text("All sounds: CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/).\n"
    "ATLAS edits: trimmed, mixed, normalized, faded, converted to mono Vorbis.\n\n" +
    "\n".join(f"{name}: {author}\n{url}\nCC0-1.0\n" for name, author, url in credits), encoding="utf-8")
(OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
assert len(manifest) == 31
print(f"Prepared {len(manifest)} sounds, {sum(p.stat().st_size for p in OUTPUT.glob('*.ogg')):,} bytes")
