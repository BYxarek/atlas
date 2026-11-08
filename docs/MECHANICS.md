# Game mechanics

[Documentation](README.md) · [Русский](MECHANICS.ru.md)

## Starting and winning

Choose any of the 239 territories and a color. Every player starts with 180 coins, 35 infantry, 8 aircraft and 4 ships, regardless of the chosen country. Conquer the entire map to win. Your army and technologies are shared across your territories. Neutral armies use the included game balance data, not real troop counts.

## Economy and army

Each country has 1–5 businesses. A business earns its level in coins per game second; upgrading costs `25 × current level` and adds one coin per second. Income stacks across controlled countries. Solo pause and a closed game generate no income.

| Troop type | Recruitment | Base strength per unit |
| --- | --- | --- |
| Infantry | 10 for 12 coins | 1 |
| Aircraft | 3 for 28 coins | 3 |
| Ships | 2 for 36 coins | 4 |

Technology starts at level 1. Each additional level adds 25% of base strength to that troop type; research costs `65 × current level`. Effective strength is the sum of `unit count × base strength × (1 + 0.25 × (technology level − 1))`.

## Reconnaissance and attacks

A spy costs 20 coins and returns after 6 game seconds. Only one spy mission runs at a time. Reports show a snapshot, not a live enemy army. Scout again after an opponent has had time to recruit.

An attack on a neighbor of any owned country costs 25 coins. Other targets cost 55 coins, require at least four ships and apply a 15% strength penalty. One outgoing offensive operation can run at a time. Troops travel for 4 game seconds; battle uses armies and technologies at arrival. The attacker wins on equal or greater effective strength. Both sides take losses; victory transfers the territory and businesses and awards 30 coins.

## Solo defense and nuclear weapons

The final remaining country is protected against solo invasions. After expansion, rumors warn of a possible invasion 60–300 game seconds ahead. A rumor becomes an attack with 60% probability; confirmed troops travel for 5 seconds. Without reconnaissance the attacker name and exact army are hidden. Neutral countries receive one infantry every 30 seconds. Capturing an invader's country cancels its pending invasion.

Every ten first-time conquests grant one nuclear charge. The starting country and recaptures do not count. A missile travels for 3 seconds, halves every defending troop count (rounded down) and does not capture land. If the target becomes yours before impact, the strike is canceled and its charge returned.

## Multiplayer differences and saves

Rooms contain up to 239 humans/bots, each with separate money, army, technology and intelligence. PvP can eliminate a player's last territory. The personal menu does not pause an online match; return everyone to the lobby for a shared pause. Backends and identity handling are explained in [Multiplayer](MULTIPLAYER.md).

Autosaves run every 15 game seconds and on important actions; manual snapshots remain separate. See [Playing](PLAYING.md) for controls, backup recovery and storage paths. Simulated sea access and combat are intentionally simplified; there is no tactical battlefield, diplomacy or offline income.

## Wars and rebels

Bots announce 80% of attacks on players; 20% are surprises, hidden until battle. Solo campaigns also allow rarer surprise invasions while retaining last-country invasion protection. Crossed swords mark hostile countries after failed attacks and territorial losses. Some strong countries have rebels: base army power at least 300 and every third map entry. They reduce defense by a random 1–10%. After a random 2–7 minutes of occupation, a 20% uprising chance repeats after another random 2–7 minutes and can return the country to its previous owner. War and uprising state is saved. See [Multiplayer](MULTIPLAYER.md) for room rules.

## Battle reports and bot strategies

Notifications and the journal retain 20 battle reports with final strength, technology contribution, naval penalty, rebel assistance and losses per branch. Both participants receive reports online; they record the battle rather than current intelligence. Reports persist with saves.

Network-room bots receive an economic, aggressive or cautious strategy with random risk, economic and recruitment preferences. New sessions roll new profiles independently of country; reconnects and saves preserve them. Solo neutral invasions retain their existing behavior.

## Map, dependencies and hidden microstates

The atlas has 244 countries and territories, including 239 starting choices. Foreign countries without a personal scout report are gray. Scouted countries use their political group color; the main country and its dependencies share a base color. Active player ownership takes precedence. Cards name the main country and its dependent territories. These geographic links do not automatically transfer territory, troops or income.

Vatican and San Marino start hidden inside Italy; Monaco inside France; Andorra between France and Spain; Liechtenstein between Austria and Switzerland. Hidden states cannot be selected, scouted, attacked or chosen as a starting seat. The first successful conquest of any surrounding country reveals each hidden state: 50% join peacefully and provide their businesses, 50% remain independent and declare war. A declaration marks a hostile target; it does not launch an immediate counterattack. The result is global online, saved and never rolled again on recapture. Peaceful accession grants no loot, victory count or nuclear-conquest credit. Hidden states in a player's starting homeland do not block world victory. Island microstates remain separate.
