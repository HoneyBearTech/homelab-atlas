# Architecture

homelab-atlas is the Docker Compose definition of **Atlas**, a homelab media automation server: the apps
that find, download, rename and subtitle media, and Recyclarr, which keeps their quality settings in line
with the TRaSH Guides. The repository holds configuration, not application code: the apps run from their
upstream images, pinned by digest.

> **Planned.** The services below are being moved into this repository; until `compose.yaml` lands, the
> list is the target, not what the repository contains.

## Services (planned)

| Service | Image source | Role |
| --- | --- | --- |
| Radarr, Radarr 4K | linuxserver.io | Movies: monitors, grabs releases, renames and imports into the library |
| Sonarr, Sonarr 4K | linuxserver.io | TV series, as Radarr does for movies |
| Lidarr | linuxserver.io | Music |
| Bazarr, Bazarr 4K | linuxserver.io | Subtitles for what Radarr and Sonarr imported |
| SABnzbd | linuxserver.io | Usenet download client |
| FlareSolverr | the project's own image | Proxy that solves browser challenges for indexers that need it |
| Recyclarr | the project's own image | Syncs TRaSH Guides custom formats and quality profiles into Radarr and Sonarr on a schedule |

The 4K instances are separate containers with their own config and library folders, so 4K and regular
releases are managed independently.

## Actors and actions

| Actor | Does |
| --- | --- |
| Maintainer | Merges pull requests, tags releases, runs `git pull` / `docker compose up -d` on the host, configures each app in its web UI |
| Dependabot | Opens a pull request when an image (tag and digest), a check tool or an Action has a new version |
| CI | Lints, scans for secrets, tests the checker, resolves the Compose file and enforces the policy on every pull request |
| Release workflow | On a version tag: checks the policy, writes the SBOM, signs the checksums, publishes the GitHub Release |
| The apps | Talk to each other's APIs on the stack's network, to indexers and the Usenet provider on the internet, and read and write `/data` |
| LAN users | Use the apps' web UIs, behind each app's own authentication |

## Data flow

```
indexers (internet) ──search──▶ Radarr / Sonarr / Lidarr ──send release──▶ SABnzbd ──download──▶ /data/usenet
                                        │                                                      │
                                        └──────────── import (hardlink / move) ◀───────────────┘
                                                             │
                                                     /data/media ──▶ Bazarr (subtitles) ──▶ media server (elsewhere)
Recyclarr ──API, daily──▶ Radarr / Sonarr (custom formats, quality profiles from the TRaSH Guides)
```

All the apps share one `/data` mount so imports are hardlinks or instant moves on one filesystem. Each app
has its own `/config` directory under `APPDATA_ROOT`. The indexer manager (Prowlarr) and the media server
run outside this stack.

## How changes reach the host

1. Dependabot (or the maintainer) opens a pull request that changes an image's tag and digest.
2. CI resolves the Compose file and runs the policy check; the maintainer reads the app's release notes.
3. The pull request is squash-merged; a version tag makes a signed release.
4. On the host: back up, `git checkout <tag>`, `docker compose pull && docker compose up -d`
   ([upgrading.md](upgrading.md)).

Nothing on the host updates itself: a version that runs is always a version that's in git.

## Repository layout

| Path | What |
| --- | --- |
| `compose.yaml` | The stack (planned) |
| `.env.example` | Every setting, with safe placeholders |
| `scripts/check_compose.py` | The policy check and SBOM generator (standard-library Python) |
| `tests/` | Its tests, with JSON fixtures |
| `docs/` | This documentation |
| `.github/` | CI, release and security workflows, Dependabot, templates |
