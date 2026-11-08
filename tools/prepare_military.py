"""Convert the checked GFP 2026 ranking into ATLAS's own gameplay calibration.

tools/gfp_order.txt is the local input (one country per line in rank order).
The source ranking and PowerIndex table are not included in the game export.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
names = (ROOT / "tools/gfp_order.txt").read_text(encoding="utf-8").splitlines()
assert len(names) == 145 and len(set(names)) == 145
aliases = {"United States": "United States of America", "Turkiye": "Turkey", "Serbia": "Republic of Serbia",
           "Tanzania": "United Republic of Tanzania", "Beliz": "Belize"}
ranks = {aliases.get(name, name): i + 1 for i, name in enumerate(names)}
world = json.loads((ROOT / "assets/world.json").read_text(encoding="utf-8"))
landlocked = set("Afghanistan|Armenia|Austria|Azerbaijan|Belarus|Bhutan|Bolivia|Botswana|Burkina Faso|Burundi|Central African Republic|Chad|Czechia|Ethiopia|Hungary|Kazakhstan|Kosovo|Kyrgyzstan|Laos|Lesotho|Luxembourg|North Macedonia|Mali|Moldova|Mongolia|Nepal|Niger|Paraguay|Rwanda|Republic of Serbia|Slovakia|South Sudan|eSwatini|Switzerland|Tajikistan|Turkmenistan|Uganda|Uzbekistan|Zambia|Zimbabwe|Andorra|Liechtenstein|San Marino|Vatican".split("|"))
armies = []
covered = 0
for country in world:
    rank = ranks.get(country["english"])
    covered += rank is not None
    # This curve and the 58/24/18 force mix are game design, not GFP's formula.
    budget = round(7000 / ((rank + 7) / 8) ** 1.65) if rank else 36
    air = int(budget * 0.24 / 3)
    navy = 0 if country["english"] in landlocked else int(budget * 0.18 / 4)
    army = [budget - 3 * air - 4 * navy, air, navy]
    assert min(army) >= 0 and sum(a * w for a, w in zip(army, [1, 3, 4])) == budget
    armies.append(army)
unmapped = sorted(set(ranks) - {country["english"] for country in world})
assert not unmapped, unmapped
data = {"balance_version": 2026, "checked_on": "2026-11-03", "source": "https://www.globalfirepower.com/countries-listing.php",
        "source_year": 2026, "ranked_map_countries": covered, "unranked_power": 36, "armies": armies}
(ROOT / "assets/military.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
print(f"Prepared {len(armies)} armies; {covered} mapped from GFP 2026; {len(armies) - covered} unranked fallbacks")
