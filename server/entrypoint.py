"""Translate Docker stop signals into a graceful Godot save and shutdown."""
from pathlib import Path
import os
import signal
import subprocess
import sys

marker = Path(os.environ.get("ATLAS_DATA_DIR", "/data")) / ".stop"
marker.unlink(missing_ok=True)
process = subprocess.Popen([
    "/usr/local/bin/godot", "--headless", "--main-pack", "/app/AtlasServer.pck", "--", "--server"
])


def stop(_signal, _frame):
    marker.touch()


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
sys.exit(process.wait())
