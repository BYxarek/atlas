# Multiplayer

[Documentation index](README.md)

Use clients and server files from the same release. There is no central account service or mandatory official server. Rooms hold up to eight humans/bots. Each player chooses an available country and color, confirms readiness, and the room administrator starts or resumes the match. The administrator can add bots and remove seats; removing a player makes their territories neutral.

## Connection options

- **LAN:** create a lobby on one client; other clients discover it on the local network or enter the host address and port. Allow the game through the host firewall. LAN discovery depends on the router/Wi-Fi permitting local broadcast traffic.
- **VPS:** enter `wss://atlas.example.com` and select/create a room. The Linux server owns simulation and saves; no client port forwarding is needed. [Deployment](../server/README.en.md).
- **PHP hosting:** enter `https://example.com/atlas` in the PHP/HTTPS server mode. The backend owns simulation, uses file storage and receives short polling requests. No persistent process or Docker is needed. [Deployment](../hosting/README.en.md).

A room code identifies a room; it is not a password. Server room lists are visible to connected users. VPS/PHP hosting is intended for a small community; hosting capacity has not been benchmarked.

## Pause and return

Esc opens a personal menu without stopping an online match. Returning everyone to the lobby pauses the room. A disconnected player also leads to a room pause (PHP defaults to a 20-second presence timeout). Reconnect to the same server using the same local profile. All remaining players must reconnect and ready up, or the administrator removes absent seats. Connected humans can inherit administration when the previous administrator leaves.

VPS rooms restore paused after a server restart. Back up server data before upgrades. LAN, VPS and PHP save formats are separate and have no automatic migration between modes. The current VPS/LAN wire version is 7; PHP protocol is 1. Public release numbering does not change those protocols.

The local profile file `network_identity.cfg` is private. Windows stores it under `%APPDATA%/AtlasWorldGame`; Android uses private app storage. A different server address produces a different server identity. No automatic profile transfer between phone and PC is provided.
