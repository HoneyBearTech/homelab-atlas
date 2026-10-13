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

| What | Where on the host | In the container |
| --- | --- | --- |
| Each app's settings, API key and database | Docker volume `<CONFIG_VOLUME_PREFIX><app>` (radarr, radarr4k, sonarr, sonarr4k, lidarr, bazarr, bazarr4k, sabnzbd) | `/config` |
| Downloads and media | `MEDIA_ROOT` | `/media` |
| Radarr's custom scripts | `APPDATA_ROOT/radarr/scripts`, `APPDATA_ROOT/radarr4k/scripts` | `/scripts` |
| SABnzbd's unfinished downloads (not backed up) | `SABNZBD_INCOMPLETE_PATH` | `/incomplete` |
| Recyclarr's config | `RECYCLARR_CONFIG_PATH` | `/config` |

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
2. Create `.env` from `.env.example` (mode `600`) and set every value. Optionally create `autoheal.env` from
   `autoheal.env.example` (mode `600`) with a webhook URL for restart notices
   ([interfaces.md](interfaces.md)).
3. Create the host directories, then `docker compose up -d`.

**Adopting existing containers.** If the apps already run on the host (for example from a Portainer stack),
set `CONFIG_VOLUME_PREFIX` to the prefix their volumes use (`docker volume ls`), so the stack takes over the same
settings and databases, and keep `MEDIA_ROOT` pointing at the directory they mount at `/media`. Stop and remove
the old containers first: the container names (`radarr`, `sonarr`, …) must be free. Docker Compose warns that
the volumes "already exist but were not created by Docker Compose"; that's expected.

Running `main` instead of a release is possible but unsupported for anything you depend on.

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
2. **On this host**, as the user who runs the stack, install rsync and curl (and pigz, which compresses faster),
   and create a key used only for the backups, with an alias for it in `~/.ssh/config`:

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
   minute or two per app), and is compressed after it has started again.
5. **Schedule it**, with the systemd user units in [`deploy/systemd/`](../deploy/systemd/) (they expect the
   checkout at `~/homelab-atlas`; edit both paths in the `.service` file if it's elsewhere). Lingering lets the
   timer run while you're logged out:

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
  Docker-published ports bypass host firewalls such as `ufw`.
- **The Dozzle agent can read every container's logs and, through the Docker socket, control Docker**, for any
  Dozzle that connects to it. Keep its port (7007) on the LAN only.
- Keep `.env` and `autoheal.env` at mode `600`. `.env` holds no secrets by design, but it does describe your
  host; `autoheal.env` holds the webhook URL.
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
