# ATLAS VPS server

[Русский](README.md)

Use Linux x86_64/amd64 with Docker Engine, Compose v2, a domain pointing to the VPS and free inbound TCP ports 80/443. Add an AAAA record only if IPv6 works. Game port 24760 stays internal to Docker.

Extract `Atlas-VPS-Source.zip` preserving directories. In `server`:

```sh
cp .env.example .env
# Edit the domain and certificate contact email in .env.
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 atlas caddy
```

Example `.env`:

```dotenv
ATLAS_DOMAIN=atlas.example.com
ACME_EMAIL=you@example.com
ATLAS_MAX_ROOMS=8
```

Enter only the domain, without scheme/path/port. Room limits are 1–32 including inactive/saved rooms; each has up to 176 player/bot slots. Start small and measure load. The build downloads checksum-verified Godot 4.8-beta2 and creates the server pack. Caddy obtains and renews HTTPS certificates; DNS and ports must already work.

Connect from the matching Windows or Android release using `wss://atlas.example.com`. Create/join a room, choose country/color and confirm readiness. The administrator manages bots/seats and starts the match. Room codes are public identifiers, not passwords. There is no global server directory or central account service.

## Pause and reconnect

The personal menu does not stop the online room. Return everyone to the lobby to pause. Disconnects also pause the room. Remaining seats must reconnect and ready up or be removed by the administrator. Administration can pass to another connected human. Removed territories become neutral. Empty rooms can be deleted by their administrator, including their saves/backups.

Rooms save important transitions and every 15 game seconds, then restore paused after restart. Keep your private local `network_identity.cfg` and the same server address to recover a seat. LAN/PHP saves do not migrate automatically.

## Backups and updates

Room `session_*.json` and `.json.bak` files live in the named `atlas-data` volume. `docker compose down` retains data; **do not use `down -v` when preserving games or certificates**.

Consistent backup:

```sh
mkdir -p backups
docker compose stop atlas
docker compose cp atlas:/data/. ./backups/
rm -f ./backups/.stop
docker compose start atlas
```

Restore only desired session files and backups, with no `.stop` file:

```sh
docker compose stop atlas
docker compose cp ./backups/. atlas:/data/
docker compose start atlas
```

Keep damaged files separately before replacing them with `.json.bak`. Invalid/incompatible files are logged rather than silently deleted. Graceful shutdown allows 20 seconds to save; a crash may lose changes since the last save.

Back up before updating, replace source with the matching release and run `docker compose up -d --build`. Stop with `docker compose down`.

## Diagnosis and development

Check DNS, firewall, Caddy/atlas logs, writable `/data`, room limits and save compatibility. Reducing the limit below the number of saved rooms can leave some unloaded; restore the limit or move unnecessary saves aside while stopped.

Without Docker, run `godot --headless --path /absolute/path/to/atlas -- --server`, setting `ATLAS_DATA_DIR`, `ATLAS_MAX_ROOMS` and optionally `ATLAS_PORT` (default 24760). Put external traffic behind TLS. Plain `ws://` is accepted only for localhost/127.0.0.1 development.

This backend is intended for small communities: connected users can create rooms up to the configured limit. No payment system or separate moderation dashboard is included. Production Docker/TLS deployment and hosting capacity were not verified in the Windows development environment.
