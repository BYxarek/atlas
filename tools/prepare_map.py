"""Convert Natural Earth public-domain polygons into the game's compact map."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT / "tools/countries.geojson").read_text(encoding="utf-8"))
countries = []
vertices = []
for feature in source["features"]:
    p, geometry = feature["properties"], feature["geometry"]
    if p["ADMIN"] == "Antarctica":
        continue
    polygons = geometry["coordinates"]
    if geometry["type"] == "Polygon":
        polygons = [polygons]
    rings = [[[round(x, 3), round(y, 3)] for x, y, *_ in polygon[0]] for polygon in polygons]
    points = {tuple(point) for ring in rings for point in ring}
    vertices.append(points)
    largest = max(rings, key=lambda ring: abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:]))))
    center = [sum(v[k] for v in largest[:-1]) / (len(largest) - 1) for k in (0, 1)]
    countries.append({"id": len(countries), "name": p.get("NAME_RU") or p["ADMIN"],
                      "english": p["ADMIN"], "continent": p["CONTINENT"],
                      "center": center, "rings": rings, "neighbors": []})
for i, country in enumerate(countries):
    country["neighbors"] = [j for j in range(len(countries)) if j != i and vertices[i] & vertices[j]]
additions = json.loads((ROOT / "tools/map_additions.json").read_text(encoding="utf-8"))
for country in additions["countries"]:
    countries.append({**country, "id": len(countries), "neighbors": []})
ids = {c["english"]: c["id"] for c in countries}
for addition in additions["countries"]:
    i = ids[addition["english"]]
    for name in addition["neighbors"]:
        j = ids[name]
        if j not in countries[i]["neighbors"]: countries[i]["neighbors"].append(j)
        if i not in countries[j]["neighbors"]: countries[j]["neighbors"].append(i)
for country in countries:
    country["sovereign"] = ids[additions["sovereigns"].get(country["english"], country["english"])]
    country["enclave_hosts"] = [ids[name] for name in additions["enclaves"].get(country["english"], [])]
for country in countries:
    country["dependencies"] = [c["id"] for c in countries if c["sovereign"] == country["id"] and c["id"] != country["id"]]
assert len(countries) == 244
assert all(c["rings"] and c["name"] for c in countries)
(ROOT / "assets/world.json").write_text(json.dumps(countries, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"Prepared {len(countries)} countries")
