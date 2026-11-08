"""Generate the Earth surface, inland water and forest textures with Pillow."""
import json
from pathlib import Path
import sys
import tempfile
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SIZE = (3600, 1450)
NE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/'
MARBLE = ('https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/'
          'bmng-base/july/world.200407.3x5400x2700.jpg')
MODIS = 'https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?' + urllib.parse.urlencode({
    'SERVICE': 'WMS', 'VERSION': '1.1.1', 'REQUEST': 'GetMap', 'SRS': 'EPSG:4326',
    'LAYERS': 'MODIS_Combined_L3_IGBP_Land_Cover_Type_Annual', 'STYLES': '',
    'BBOX': '-180,-60,180,85', 'WIDTH': 1440, 'HEIGHT': 580, 'FORMAT': 'image/png',
    'TIME': '2022-01-01',
})

# Red and green carry needleleaf and broadleaf forest density respectively.
FOREST_CLASSES = {
    (33, 138, 33): (255, 0, 0),
    (49, 204, 49): (0, 255, 0),
    (152, 204, 49): (255, 0, 0),
    (150, 250, 150): (0, 255, 0),
    (141, 186, 141): (128, 127, 0),
    (218, 235, 157): (0, 78, 0),
}


def source(cache, name, url):
    path = cache / name
    if not path.exists():
        with urllib.request.urlopen(url, timeout=90) as response:
            path.write_bytes(response.read())
    return path


def pixel(point, size=SIZE):
    return ((point[0] + 180) * size[0] / 360, (85 - point[1]) * size[1] / 145)


def draw_river(painter, points, size, width):
    start = 0
    for end in range(1, len(points) + 1):
        if end == len(points) or abs(points[end][0] - points[end - 1][0]) > 180:
            if end - start > 1:
                painter.line([pixel(p, size) for p in points[start:end]], fill=255, width=width, joint='curve')
            start = end


def water_texture(rivers, lakes):
    water_size = (4096, 1650)
    oversampled = tuple(size * 2 for size in water_size)
    lake_mask, major, minor = (Image.new('L', oversampled) for _ in range(3))
    lake_draw, major_draw, minor_draw = (ImageDraw.Draw(layer) for layer in (lake_mask, major, minor))
    for feature in lakes:
        shape = feature['geometry']
        polygons = shape['coordinates'] if shape['type'] == 'MultiPolygon' else [shape['coordinates']]
        for polygon in polygons:
            for index, ring in enumerate(polygon):
                lake_draw.polygon([pixel(p, oversampled) for p in ring], fill=255 if index == 0 else 0)
    for feature in rivers:
        if feature['properties']['featurecla'] == 'Lake Centerline':
            continue
        shape = feature['geometry']
        lines = shape['coordinates'] if shape['type'] == 'MultiLineString' else [shape['coordinates']]
        rank = feature['properties']['scalerank']
        for line in lines:
            draw_river(major_draw if rank <= 4 else minor_draw, line, oversampled, 2 if rank <= 4 else 1)
    assert lake_mask.getpixel(tuple(map(int, pixel((-88.2, 47.6), oversampled)))) == 255
    assert major.getbbox() and minor.getbbox()
    return Image.merge('RGB', tuple(layer.resize(water_size, Image.Resampling.BOX) for layer in (lake_mask, major, minor)))


def main():
    cache = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.gettempdir())
    cache.mkdir(parents=True, exist_ok=True)
    image = Image.open(source(cache, 'atlas-marble-source.jpg', MARBLE)).convert('RGB')
    assert image.size == (5400, 2700)
    image.crop((0, 75, 5400, 2250)).resize(SIZE, Image.Resampling.LANCZOS).save(
        ROOT / 'assets/earth_land.jpg', quality=91, optimize=True)

    rivers = json.loads(source(cache, 'atlas-natural-rivers.json', NE + 'ne_10m_rivers_lake_centerlines.geojson').read_bytes())
    lakes = json.loads(source(cache, 'atlas-natural-lakes.json', NE + 'ne_10m_lakes.geojson').read_bytes())
    water_texture(rivers['features'], lakes['features']).save(ROOT / 'assets/earth_inland_water.png', optimize=True)

    cover = Image.open(source(cache, 'atlas-modis-2022.png', MODIS)).convert('RGBA')
    assert cover.size == (1440, 580)
    forest = Image.new('RGB', cover.size)
    forest.putdata([FOREST_CLASSES.get(p[:3], (0, 0, 0)) if p[3] == 255 else (0, 0, 0)
                    for p in cover.get_flattened_data()])
    forest = forest.resize((720, 290), Image.Resampling.BOX)
    amazon = forest.getpixel(tuple(map(int, pixel((-62, -4), forest.size))))
    sahara = forest.getpixel(tuple(map(int, pixel((10, 25), forest.size))))
    assert sum(amazon) > 190 and sum(sahara) == 0
    forest.save(ROOT / 'assets/earth_forests.png', optimize=True)
    print('PASS: satellite colors, inland water and MODIS forest textures prepared')


if __name__ == '__main__':
    main()
