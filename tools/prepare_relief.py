"""Build the small ATLAS terrain texture from NOAA ETOPO 2022 (60 arc seconds)."""
import csv
from pathlib import Path
import struct
import sys
import urllib.request
import zlib


SOURCE = (
    'https://oceanwatch.pifsc.noaa.gov/erddap/griddap/ETOPO_2022_v1_60s.csv0'
    '?z%5B1800:60:10500%5D%5B0:60:21599%5D'
)
WIDTH, HEIGHT = 361, 146
ROOT = Path(__file__).resolve().parents[1]


def png_chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def main():
    # Accept an already downloaded CSV for reproducible offline runs.
    if len(sys.argv) > 1:
        source = Path(sys.argv[1]).read_text(encoding='ascii')
    else:
        with urllib.request.urlopen(SOURCE, timeout=180) as response:
            source = response.read().decode('ascii')
    elevations = {
        (round(float(lat)), round(float(lon)) % 360): float(elevation)
        for lat, lon, elevation in csv.reader(source.splitlines())
    }
    assert len(elevations) == (HEIGHT * (WIDTH - 1))
    assert elevations[46, 8] > 1000 and elevations[0, 200] < -1000
    rows = []
    for latitude in range(85, -61, -1):
        row = bytearray([0])
        for longitude in range(-180, 181):
            elevation = elevations[latitude, longitude % 360]
            land = round(min(1, max(0, elevation / 6000)) ** 0.75 * 255)
            depth = round(min(1, max(0, -elevation / 4500)) ** 0.55 * 255)
            row.extend((land, depth, 0))
        rows.append(row)
    png = b'\x89PNG\r\n\x1a\n'
    png += png_chunk(b'IHDR', struct.pack('>IIBBBBB', WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += png_chunk(b'IDAT', zlib.compress(b''.join(rows), 9))
    png += png_chunk(b'IEND', b'')
    output = ROOT / 'assets' / 'earth_relief.png'
    output.write_bytes(png)
    print(f'{output.name}: {WIDTH} × {HEIGHT}, {len(png):,} bytes')


if __name__ == '__main__':
    main()
