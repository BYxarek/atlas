# ATLAS on PHP shared hosting

[Русский](README.md)

Only a domain directory, HTTPS, PHP settings and cron are needed. No Docker, SSH, Node.js, database or persistent Godot process is required. PHP calculates economy, armies, spies, bots and combat; clients submit commands.

## Installation

1. Extract `Atlas-PHP-Hosting.zip` into a separate domain folder, such as `atlas`, using FTP or the hosting file manager. Keep it separate from an existing website.
2. Enable PHP 8.1+ with JSON, Hash, PCRE, `random_bytes` and filesystem operations including `flock`/`rename`. Process execution is not used.
3. Enable a valid SSL certificate. The client verifies it and connects to `https://example.com/atlas`.
4. Copy `config.example.php` to `config.php`. PHP must be able to create/write `_data`. Use appropriate ownership/permissions rather than 777.
5. Open the folder URL to check the landing page. In the client select PHP hosting / HTTPS, enter that URL and connect.

A full `/api.php` URL also works. Query parameters, redirects and unusual path characters are unsupported. Exclude the API from browser CAPTCHA challenges. Plain HTTP is only allowed for localhost development.

## Cron

Add a once-per-minute task in the hosting panel, using the provider's actual paths:

```cron
* * * * * /usr/bin/php /home/USER/www/example.com/atlas/cron.php
```

CLI cron needs no key. For URL-only schedulers configure a random `cron_key` of at least 32 characters. HTTP cron is disabled by default. Prefer an `Authorization: Bearer YOUR_KEY` header. The fallback `cron.php?key=YOUR_KEY` may appear in logs; keep it private and never reuse a hosting password.

Cron exits after a short request. Client requests also advance time, so a minute cron interval does not imply minute-long input latency.

## Rooms and capacity

Rooms support up to 239 humans/bots. The administrator manages seats and starts after everyone is ready. Start resources are equal: 35 infantry, 8 aircraft, 4 ships and 180 coins. PvP can eliminate the last territory. Exact enemy troops remain hidden until personal reconnaissance. Retrying an accepted command does not duplicate its purchase.

Returning to the lobby pauses the room. Lost connections pause after the presence lease, default 20 seconds. Reconnect using the same profile and server address; after abrupt disconnects wait up to the lease duration. Administration can transfer to another connected human. Room codes are identifiers, not passwords. VPS/PHP/LAN saves remain separate.

Defaults are `max_rooms=4`, `poll_ms=1000`, `lease_seconds=20`. Allowed ranges: 1–16 rooms, 750–5000 ms polling, 10–120 seconds lease. Keep the lease comfortably above polling. Start with one or two rooms on small plans. Each client produces roughly one request per second plus actions. Check provider CPU/request limits; use VPS for larger groups. Hosting capacity has not been benchmarked.

## Data, backups and updates

`data_dir` defaults to `_data`, containing `state.php`, `backup.php` and `lock.php`. API and cron share a file lock; writes replace files through temporary files. Storage errors do not silently reset the database.

Prefer a directory outside the web root when permitted. Otherwise PHP data-file guards return 404, with additional Apache restrictions in `.htaccess`. Verify PHP executes and is never served as text. Keep those protections when changing web-server rules.

For consistent backups disable API access and cron in the panel, download `state.php` and `backup.php`, then re-enable access. Restore while requests are stopped by replacing `state.php` with the chosen backup, retaining its protective first PHP line. Keep the lock file. Do not edit stored JSON manually.

Before upgrades back up data, then replace program files only, preserving `config.php` and all of `data_dir`. Use client/backend files from the same release (PHP protocol 2).

For HTML responses instead of JSON check URLs, redirects, CAPTCHA, PHP errors and ModSecurity. For storage failures check write permissions, free disk and private PHP logs. Never expose debug errors, paths or stored data in public API responses. If `.htaccess` produces HTTP 500, consult the provider and retain the PHP guards.

## Diagnostics and consistent backups

Set `metrics=true` in your private config to log numeric request/storage timings to the PHP error log. Metrics contain no identities or request bodies. Optional CLI: `php storage.php backup DATA_DIRECTORY SNAPSHOT_FILE` and `php storage.php restore DATA_DIRECTORY SNAPSHOT_FILE`. Store snapshots outside the public web root; use the existing stopped-API FTP procedure when CLI is unavailable. Restore preserves `before-restore.php`. See `docs/TECHNICAL_IMPROVEMENTS.ru.md` in the source repository for the coordinated client/server update and rollback procedure.


Network mods / Сетевые моды: [единый формат .atlasmod для LAN, VPS и PHP](../docs/MODS.md). Папка: `network_mods/` рядом с `api.php`; обновляйте клиент и сервер вместе (PHP protocol 5).
