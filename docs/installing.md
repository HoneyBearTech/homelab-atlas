# Installing

The [quick start](quick-start.md) is the short version of this page.

## Requirements

- Linux on amd64 (the reference is Ubuntu 24.04 LTS) with Docker Engine and the Compose v2 plugin
  (Docker Engine 25 or later and Compose 2.24 or later, for the health checks' `start_interval`).
- A user in the `docker` group to run `docker compose`. Membership is equivalent to root on the host, so keep
  that group small.
- One directory for `MEDIA_ROOT` that holds **both downloads and the library on the same filesystem**, so the
  apps can hardlink and move files instead of copying them. A network share works if the whole tree is one
  export.

## Where data lives

Every app's own data lives in one folder per app under `CONFIG_ROOT`, named after its service: its settings and
database in `CONFIG_ROOT/<app>/config`, anything else of its own beside that (`CONFIG_ROOT/<app>/<purpose>`).

| What | Where on the host | In the container |
| --- | --- | --- |
| Each app's settings, API key and database | its config directory, `CONFIG_ROOT/<app>/config` (radarr, radarr4k, sonarr, sonarr4k, lidarr, bazarr, bazarr4k, sabnzbd) | `/config` |
| Recyclarr's config (`recyclarr.yml`) | `CONFIG_ROOT/recyclarr/config` | `/config` |
| Seerr's settings, API key and database (its `logs` folder isn't backed up) | `CONFIG_ROOT/seerr/config` | `/app/config` |
| Radarr's custom scripts | `CONFIG_ROOT/radarr/scripts`, `CONFIG_ROOT/radarr4k/scripts` | `/scripts` |
| Downloads and media | `MEDIA_ROOT` | `/media` |
| SABnzbd's unfinished downloads (not backed up) | `SABNZBD_INCOMPLETE_PATH` | `/incomplete` |

```
$CONFIG_ROOT/
  radarr/{config,scripts}/  radarr4k/{config,scripts}/
  sonarr/config/  sonarr4k/config/  lidarr/config/  bazarr/config/  bazarr4k/config/  sabnzbd/config/
  recyclarr/config/  seerr/config/
```

> **Warning: never point a path setting into `/var/lib/docker/volumes`, and don't keep app data in named Docker
> volumes.** `docker volume prune`, `docker system prune --volumes` and Portainer's "remove unused volumes" delete
> every volume that no container mounts *as a volume*, including one whose `_data` folder a service bind-mounts
> through a path setting: Docker counts that volume as unused, and the app's settings and database go with it. Keep
> every app's data under `CONFIG_ROOT`, outside Docker's own directories, and back it up.

An example layout under `MEDIA_ROOT`, following the TRaSH Guides:

```
$MEDIA_ROOT/
  usenet/{incomplete,complete}/
  movies/  movies4k/  tv/  tv4k/  music/
```

The apps save `/media/...` paths in their databases, so keep the container path the same if you move hosts.
`MEDIA_ROOT` and every folder under `CONFIG_ROOT` must be readable and writable by `PUID:PGID`. Create the folders
as that user before the first start: Docker creates a missing one owned by root, and Recyclarr and Seerr, which run
as `PUID:PGID` without capabilities, can't write to that.

## Installing

1. Clone the repository (or download a release's source archive and verify it,
   [verifying-releases.md](verifying-releases.md)).
2. Create `.env` from `.env.example` (mode `600`) and set every value. Optionally create `autoheal.env` from
   `autoheal.env.example` (mode `600`) with a webhook URL for restart notices
   ([interfaces.md](interfaces.md)).
3. Create the host directories as the `PUID` user (`MEDIA_ROOT`, `SABNZBD_INCOMPLETE_PATH` and each folder under
   `CONFIG_ROOT` in the layout above; the [quick start](quick-start.md) has the commands), then
   `docker compose up -d`.

**Adopting existing containers.** If the apps already run on the host (for example from a Portainer stack), copy
each app's config into its config directory (Recyclarr's into `CONFIG_ROOT/recyclarr/config`, Radarr's scripts into
`CONFIG_ROOT/<app>/scripts`) so the stack takes over the same settings and databases, and keep `MEDIA_ROOT` pointing
at the directory they mount at `/media`. Stop and remove the old containers first: the container names (`radarr`,
`sonarr`, …) must be free. `docker inspect --format '{{json .Mounts}}' radarr` shows what an app mounts at `/config`
before you remove it; for a Docker volume, copy its contents with the app stopped (`cp -a` keeps the owners, which
should be `PUID:PGID`):

```sh
. ./.env && docker run --rm --network none -v <radarr's volume>:/from:ro -v "$CONFIG_ROOT/radarr/config:/to" \
  busybox cp -a /from/. /to/
```

The old volumes aren't touched: remove them (`docker volume rm`) once the apps run from their config
directories.

### Connecting the apps

Point the apps at each other by service name, on the stack's network, never by the host's address: that way they
don't depend on the host's firewall ([below](#firewall)) or address. Use the container ports, not the published
ones:

| In | Settings | Host | Port |
| --- | --- | --- | --- |
| Radarr, Radarr 4K, Sonarr, Sonarr 4K, Lidarr | Download Clients → SABnzbd | `sabnzbd` | `8080` |
| Bazarr | Sonarr / Radarr | `sonarr` / `radarr` | `8989` / `7878` |
| Bazarr 4K | Sonarr / Radarr | `sonarr4k` / `radarr4k` | `8989` / `7878` |
| Recyclarr (`recyclarr.yml`) | `base_url` of each instance | `http://sonarr:8989`, `http://sonarr4k:8989`, `http://radarr:7878`, `http://radarr4k:7878` | |
| Seerr | Settings → Services → Radarr / Sonarr (tick **4K Server** for the 4K ones, and make each the default for its kind) | `radarr`, `radarr4k` / `sonarr`, `sonarr4k` | `7878` / `8989` |

SABnzbd refuses requests for a host name it doesn't know ("Hostname verification failed") unless it has a login
set: add `sabnzbd` to Config → Special → `host_whitelist`, keeping the entries already there. If an app has a remote
path mapping (Settings → Download Clients), its Host must match the download client's new host. Apps outside this
stack (an indexer manager, a media server) keep using the host's address and published ports: Seerr reaches Plex,
on another host, by that host's address.

### Firewall

Docker-published ports bypass a host firewall such as `ufw` for other machines, but not for the stack itself: a
container that calls the host's own address on a published port of a container on the same network goes through
Docker's proxy on the host, so a firewall that denies incoming traffic by default drops it, and the apps time out
reaching each other. Calls by service name ([above](#connecting-the-apps)) stay on the stack's network and never
meet the firewall. If something on the stack must call the host's address, allow the stack's network, whose range
`STACK_SUBNET` keeps fixed (default `172.25.0.0/16`):

```sh
sudo ufw allow from 172.25.0.0/16
```

The maintainer's server runs `main` rather than a release, and deploys every merge by itself
([upgrading.md](upgrading.md#following-main)). For your own setup, a release is the safer choice.

## Scheduled backups

`scripts/scheduled-backup.sh` takes a backup (`scripts/backup.sh`), copies it to another machine with rsync, keeps
only the newest few in both places and reports to an Uptime Kuma push monitor. A systemd timer runs it nightly.
Every setting is in the optional `backup.env` ([interfaces.md](interfaces.md#backupenv)). The backups hold every
app's API keys and logins: copy them only to a machine you trust as much as this one.

1. **On the backup server**, create a folder for the backups and a user that can write only there and use rsync
   over SSH (on a Synology: a shared folder, a non-admin user with read/write on that folder only, rsync allowed
   under Application Privileges, SSH on, the rsync service on under File Services, and the user home service on so
   the user can have an `authorized_keys`). Whoever controls this host can delete or overwrite what it copied
   there, so keep older versions where the backup user can't reach them: snapshots of the folder, or a versioned
   copy of it made on the server after the nightly backup (on a Synology without Btrfs, a Hyper Backup task with
   rotation, into a folder the backup user has no access to). A recycle bin isn't enough: Synology's doesn't keep
   files deleted over rsync.
2. **On this host**, as the user who runs the stack, install rsync and curl (and pigz, which compresses the
   archives on every core instead of one), and create a key used only for the backups, with an alias for it in
   `~/.ssh/config`:

   ```sh
   sudo apt install -y rsync curl pigz
   ssh-keygen -t ed25519 -N '' -f ~/.ssh/atlas-backup
   ```

   ```text
   Host backup-host
     HostName <the backup server's address>
     User <the backup user>
     IdentityFile ~/.ssh/atlas-backup
     IdentitiesOnly yes
   ```

   Add the public key to the backup user's `~/.ssh/authorized_keys` on the server, prefixed with
   `restrict,from="<this host's address>"` (no shell or forwarding, and only from this host), then check that
   `rsync --list-only backup-host:/volume1/<folder>/` works without a password prompt.
3. **Settings**: `cp backup.env.example backup.env && chmod 600 backup.env`, then set
   `BACKUP_REMOTE=backup-host:/volume1/<folder>` and, optionally, the retention and `BACKUP_PING_URL`. For the
   ping, add a monitor of type **Push** in Uptime Kuma with a heartbeat interval of 25 hours, and copy its URL.
4. **Try it**: `scripts/scheduled-backup.sh`. Each service stops only while its own data is copied (seconds to a
   minute or two per app), and is compressed after it has started again. On a server with the pull agent, the
   backup waits for a deploy in progress and holds the next one off until it's done
   ([upgrading.md](upgrading.md#following-main)).
5. **Schedule it**, with the systemd user units in [`deploy/systemd/`](../deploy/systemd/) (they expect the
   checkout at `~/homelab-atlas`; edit both paths in the `.service` file if it's elsewhere). Lingering lets the
   timer run while you're logged out. Copy the units again after an upgrade that changes them (the release notes
   say so):

   ```sh
   mkdir -p ~/.config/systemd/user
   cp deploy/systemd/homelab-atlas-backup.* ~/.config/systemd/user/
   sudo loginctl enable-linger "$USER"
   systemctl --user daemon-reload
   systemctl --user enable --now homelab-atlas-backup.timer
   systemctl --user list-timers homelab-atlas-backup.timer     # next run: 03:00, plus up to 5 minutes
   journalctl --user -u homelab-atlas-backup                   # what the last runs did
   ```

Restore a copy from the backup server as [rebuilding.md](rebuilding.md) describes; `scripts/restore.sh` verifies
its `SHA256SUMS` first, and a copy that was cut off has none yet, so it is refused.

## Running it securely

- Turn on each app's authentication (**Forms**, required for all addresses) before anything else, and keep the
  web UIs on the LAN; put a reverse proxy with TLS and an allow-list in front of any you reach from elsewhere.
  Docker-published ports bypass host firewalls such as `ufw` (except for the stack's own calls to the host's
  address, [firewall](#firewall)).
- **The Dozzle agent can read every container's logs and, through the Docker socket, control Docker**, for any
  Dozzle that connects to it. Keep its port (7007) on the LAN only.
- Keep `.env` and `autoheal.env` at mode `600`. `.env` holds no secrets by design, but it does describe your
  host; `autoheal.env` holds the webhook URL.
- Back up `CONFIG_ROOT`: it holds every app's API key and database ([upgrading.md](upgrading.md#backing-up)).
  Never move it, or any app's data, into a Docker volume ([where data lives](#where-data-lives)).
- Keep `UMASK` at `002`: `000` makes every new file on your media share world-writable.
- Don't add services that mount the Docker socket, run privileged or use the host network without a documented
  reason; the policy check refuses them ([security.md](security.md)).
- Don't run an auto-updater (such as Watchtower) on these containers: it would replace the pinned, reviewed
  versions with whatever a tag points to today.

## Uninstalling

```sh
docker compose down          # stops and removes the containers and the stack's network
```

`CONFIG_ROOT` (every app's data), `MEDIA_ROOT` and `SABNZBD_INCOMPLETE_PATH` are left untouched. Remove the
directories by hand if you no longer want the apps' settings or your media.
