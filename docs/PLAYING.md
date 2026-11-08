# Installation, controls and saves

[Documentation index](README.md)

## Start a campaign

Download a client from GitHub Releases. On Windows extract the whole ZIP and run `Atlas.exe`. On Android install the APK and allow installation from that source when requested. Select New game on the left, choose a country and color, then start. Solo campaigns work offline.

The right side of the main menu shows the map, the installed version and a link to the project on GitHub. At startup the game checks GitHub for a newer stable release. When one is available, the game shows the release notes and adds a release link to the main menu.

In Settings, use the left navigation to switch between Interface (language and FPS), Display (map and Windows fullscreen options) and Audio (master and effects volume).

## Controls

On desktop click a country, drag the map with the left or middle mouse button and zoom with the wheel. Esc or Space opens the pause menu. On Android tap to select, drag to move and pinch to zoom; zoom buttons are also available. The bottom toolbar opens army, territories, nuclear arsenal and notifications. Back closes the current keyboard/dialog/panel before navigating the game menu.

Solo pause stops the simulation. The personal menu in multiplayer does not pause the server; return everyone to the lobby to pause the room.

## Economy and combat

Upgrade businesses for income, recruit and research infantry/aircraft/ships, then scout before attacking. Intelligence is a snapshot and can become stale. Neighboring operations cost 25 coins; overseas operations cost 55, require four ships and reduce effective strength by 15%. A spy costs 20 coins. Nuclear charges are earned for every ten first-time conquests excluding the starting country; a strike halves each troop type without transferring the territory.

Solo attack rumors arrive 60–300 game seconds before a possible invasion and may prove false. Unscouted attackers have an unknown name and approximate strength. Your single remaining territory is protected in solo play. This protection does not apply to PvP.

## Saves and profiles

Autosaves run every 15 game seconds and at important transitions. Manual snapshots are separate files. Windows data is in `%APPDATA%/AtlasWorldGame`; campaigns are in `saves`, and overwritten saves retain `.json.bak` backups. Close the game before restoring a backup. Android uses private application storage; uninstalling or clearing data removes campaigns, settings and network identity.

Online rooms are saved on their server. Your local `network_identity.cfg` identifies your seat; keep it private and backed up. There is no automatic cross-device account or cloud-save synchronization.
