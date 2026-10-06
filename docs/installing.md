# Installing

> **Planned.** The stack (`compose.yaml`) is not in the repository yet; this describes how it will be
> installed. The [quick start](quick-start.md) is the short version.

## Requirements

- Linux on amd64 (the reference is Ubuntu 24.04 LTS) with Docker Engine and the Compose v2 plugin.
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so
  keep that group small.
- Storage for `DATA_ROOT` large enough for downloads and the library. Downloads and media must be on the
  **same filesystem** under one directory, so the apps can hardlink and move files instead of copying them.

## Directory layout

```
$APPDATA_ROOT/
  radarr/  sonarr/  lidarr/  bazarr/  sabnzbd/  recyclarr/ …   one per app, mounted at /config
$DATA_ROOT/                                                     mounted at /data
  usenet/{incomplete,complete}/
  media/{movies,tv,music}/
```

This follows the TRaSH Guides' recommended layout. Both directories must be owned by `PUID:PGID`.

## Installing from a release

1. Download the release's source archive and verify it ([verifying-releases.md](verifying-releases.md)),
   or clone the repository and check out the signed tag.
2. Create `.env` from `.env.example` (mode `600`) and set every value ([interfaces.md](interfaces.md)).
3. `docker compose up -d`.

Running `main` instead of a release is possible but unsupported for anything you depend on: `main` can
move to an image version that hasn't been tried on a real host yet.

## Running it securely

- Turn on each app's authentication (**Forms**, required for all addresses) before anything else, and keep
  the web UIs on the LAN; put a reverse proxy with TLS and an allow-list in front of any you reach from
  elsewhere. Docker-published ports bypass host firewalls such as `ufw`.
- Keep `.env` at mode `600`. It holds no secrets by design, but it describes your host.
- Back up `APPDATA_ROOT`: it holds every app's API key and database ([upgrading.md](upgrading.md#backing-up)).
- Don't add services that mount the Docker socket, run privileged or use the host network without a
  documented reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned,
  reviewed versions with whatever a tag points to today.

## Uninstalling

```sh
docker compose down          # stops and removes the containers and the stack's network
```

`APPDATA_ROOT` and `DATA_ROOT` are left untouched; delete them yourself if you no longer want the apps'
settings or your media. The pulled images can be removed with `docker image prune`.
