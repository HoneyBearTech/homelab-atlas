# Architecture

homelab-atlas is the Docker Compose definition of **Atlas**, a homelab media automation server: the apps
that find, download, rename and subtitle media, and Recyclarr, which keeps their quality settings in line
with the TRaSH Guides. The repository holds configuration, not application code: the apps run from their
upstream images, pinned by digest.

## Services

| Service | Image source | Role |
| --- | --- | --- |
| Radarr, Radarr 4K | linuxserver.io | Movies: monitors, grabs releases, renames and imports into the library |
| Sonarr, Sonarr 4K | linuxserver.io | TV series, as Radarr does for movies |
| Lidarr | linuxserver.io | Music |
| Bazarr, Bazarr 4K | linuxserver.io | Subtitles for what Radarr and Sonarr imported |
| SABnzbd | linuxserver.io | Usenet download client |
| Recyclarr | the project's own image | Syncs TRaSH Guides custom formats and quality profiles into Radarr and Sonarr on a schedule |
| Seerr | the project's own image | Request front end: viewers sign in with Plex and request movies and shows, which it sends to Radarr and Sonarr (the 4K instances for 4K requests); it checks Plex, on another host, for what's already there |
| Dozzle | the project's own image | Agent that serves the containers' logs (read through the Docker socket) to the homelab's Dozzle on another host, which shows every host's logs in one web UI |
| autoheal | the project's own image | Restarts any app whose health check fails, and can post a notice to a webhook (Docker on its own only restarts a container that exits) |
| socket-proxy | linuxserver.io | Gives autoheal a filtered view of the Docker API (list, inspect, restart and stop containers only) on an internal network |

The 4K instances are separate containers with their own config and library folders, so 4K and regular
releases are managed independently.

## Actors and actions

| Actor | Does |
| --- | --- |
| Maintainer | Merges pull requests (a merge deploys), tags releases, configures each app in its web UI |
| Dependabot | Opens a pull request when an image (tag and digest), a check tool or an Action has a new version; patch, minor and major updates and image rebuilds (same tag, new digest) are auto-merged once the checks pass |
| CI | Lints, scans for secrets, tests the checker, resolves the Compose file and enforces the policy on every pull request |
| Pull agent | On the maintainer's server, about every 90 seconds: fetches `main` and, when it moved, fast-forwards the checkout and runs `docker compose pull` and `docker compose up -d` (it lives in the maintainer's private orchestration repository); skips its run while `scripts/backup.sh` or `scripts/restore.sh` holds its deploy lock |
| Release workflow | On a version tag: checks the policy, writes the SBOM, signs the checksums, publishes the GitHub Release |
| The apps | Talk to each other's APIs on the stack's network, to indexers and the Usenet provider on the internet, and read and write `/media` |
| LAN users | Use the apps' web UIs, behind each app's own authentication; viewers use Seerr, signing in with their Plex account |

## Data flow

```
indexers (internet) ──search──▶ Radarr / Sonarr / Lidarr ──send release──▶ SABnzbd ──download──▶ /media/usenet
                                        │                                                      │
                                        └──────────── import (hardlink / move) ◀───────────────┘
                                                             │
                                                     /media/<library> ──▶ Bazarr (subtitles) ──▶ media server (elsewhere)
Recyclarr ──API, daily──▶ Radarr / Sonarr (custom formats, quality profiles from the TRaSH Guides)
viewers ──request──▶ Seerr ──API──▶ Radarr / Sonarr (4K requests to the 4K instances); Seerr ◀──library scan── Plex (elsewhere)
```

All the apps share one `/media` mount (`MEDIA_ROOT`) so imports are hardlinks or instant moves on one
filesystem. Each app keeps its settings and database in its own config directory (`CONFIG_ROOT/<app>/config`),
mounted at `/config`. The indexer manager (Prowlarr), the download client for torrents and the media server run
outside this stack.

## How changes reach the host

1. Dependabot (or the maintainer) opens a pull request that changes an image's tag and digest, or only its digest
   (a rebuild of the same version).
2. CI resolves the Compose file and runs the policy check; the maintainer reads the app's release notes.
3. The pull request is squash-merged (automatically for Dependabot's patch, minor and major updates and rebuilds,
   once every check passes, with the nightly backup behind them; by the maintainer for anything else).
4. Within about 90 seconds the pull agent on the host sees `main` move, fast-forwards its checkout and runs
   `docker compose pull && docker compose up -d --remove-orphans --wait`
   ([upgrading.md](upgrading.md#following-main)). A rollback is a revert pull request, deployed the same way.
5. A version tag makes a signed release: a named, verifiable snapshot of `main`.

Nothing updates from a registry by itself: a version that runs is always a version that's in `main`. The host
only pulls; nothing connects in to it to deploy.

## Repository layout

| Path | What |
| --- | --- |
| `compose.yaml` | The stack |
| `.env.example`, `autoheal.env.example` | Templates for the settings and autoheal's optional webhook |
| `scripts/check_compose.py` | The policy check and SBOM generator (standard-library Python) |
| `tests/` | Its tests, with JSON fixtures |
| `docs/` | This documentation |
| `.github/` | CI, release and security workflows, Dependabot, templates |
