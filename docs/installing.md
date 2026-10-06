# Installing

The [quick start](quick-start.md) is the short version of this page.

## Requirements

- Linux on amd64 (the reference is Ubuntu 24.04 LTS) with Docker Engine and the Compose v2 plugin
  (2.24 or later, for `env_file` with `required`).
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so keep
  that group small.
- One directory for `MEDIA_ROOT` that holds **both downloads and the library on the same filesystem**, so the
  apps can hardlink and move files instead of copying them. A network share works if the whole tree is one
  export.
- A NUT (Network UPS Tools) server, if you keep webnut.

## Where data lives

| What | Where on the host | In the container |
| --- | --- | --- |
| Each app's settings, API key and database | Docker volume `<CONFIG_VOLUME_PREFIX><app>` (radarr, radarr4k, sonarr, sonarr4k, lidarr, bazarr, bazarr4k, sabnzbd) | `/config` |
| Downloads and media | `MEDIA_ROOT` | `/media` |
| Radarr's custom scripts | `APPDATA_ROOT/radarr/scripts`, `APPDATA_ROOT/radarr4k/scripts` | `/scripts` |
| Recyclarr's config | `RECYCLARR_CONFIG_PATH` | `/config` |
| webnut's UPS login | `webnut.env` next to `compose.yaml` | environment |

An example layout under `MEDIA_ROOT`, following the TRaSH Guides:

```
$MEDIA_ROOT/
  usenet/{incomplete,complete}/
  movies/  movies4k/  tv/  tv4k/  music/
```

The apps save `/media/...` paths in their databases, so keep the container path the same if you move hosts.
`MEDIA_ROOT` must be readable and writable by `PUID:PGID`.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` and `webnut.env` from their `.example` files (mode `600`) and set every value
   ([interfaces.md](interfaces.md)).
3. Create the host directories, then `docker compose up -d`.

**Adopting existing containers.** If the apps already run on the host (for example from a Portainer stack),
set `CONFIG_VOLUME_PREFIX` to the prefix their volumes use (`docker volume ls`), so the stack takes over the same
settings and databases, and keep `MEDIA_ROOT` pointing at the directory they mount at `/media`. Stop and remove
the old containers first: the container names (`radarr`, `sonarr`, …) must be free. Docker Compose warns that
the volumes "already exist but were not created by Docker Compose"; that's expected.

Running `main` instead of a release is possible but unsupported for anything you depend on.

## Running it securely

- Turn on each app's authentication (**Forms**, required for all addresses) before anything else, and keep the
  web UIs on the LAN; put a reverse proxy with TLS and an allow-list in front of any you reach from elsewhere.
  Docker-published ports bypass host firewalls such as `ufw`.
- **Dozzle can read every container's logs and, through the Docker socket, control Docker.** Keep its port on
  the LAN only, or turn on its own authentication.
- Keep `.env` and `webnut.env` at mode `600`. `.env` holds no secrets by design; `webnut.env` holds the UPS
  login.
- Back up the config volumes and `RECYCLARR_CONFIG_PATH`: they hold every app's API key and database
  ([upgrading.md](upgrading.md#backing-up)).
- Keep `UMASK` at `002`: `000` makes every new file on your media share world-writable.
- Don't add services that mount the Docker socket, run privileged or use the host network without a documented
  reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned, reviewed
  versions with whatever a tag points to today.

## Uninstalling

```sh
docker compose down          # stops and removes the containers and the stack's network
```

The config volumes, `MEDIA_ROOT`, `APPDATA_ROOT` and `RECYCLARR_CONFIG_PATH` are left untouched. Remove the
volumes with `docker volume rm` and the directories by hand if you no longer want the apps' settings or your
media.
