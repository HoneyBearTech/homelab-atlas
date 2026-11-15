# Rebuilding the host

How to bring the stack back on a new or wiped machine from a backup made by `scripts/backup.sh`
([upgrading.md](upgrading.md#backing-up)), with every app's settings, history and API keys as they were. The
backup and restore scripts run end to end in CI on every change (the smoke test backs up the running stack,
changes it, restores it and checks the result, and copies a scheduled backup, plain and encrypted with age, to a
stand-in backup server). This page itself is rehearsed every week and on every change to it or to the scripts: on a
fresh machine, the rehearsal runs its marked steps in order and checks the result
([below](#what-the-rehearsal-covers)).

You need: the backup directory (copied off the old host), **the age private key** it was encrypted to if the copies
off the host are encrypted (`BACKUP_AGE_RECIPIENT`), access to the media storage, and this repository.

**An encrypted copy** (the folder on the backup server holds only `backup.tar.age` and `SHA256SUMS`) is opened on
the machine that holds the age private key, never on the backup server or the new host. Copy it there and check it
(a copy that was cut off has no `SHA256SUMS`, which is sent last: take the one before), then decrypt it, which gives
the backup directory as it was written on the old host, and copy that to the new host:

<!-- rehearse: decrypt -->
```sh
rsync -rlpt backup-host:/volume1/<folder>/<date>-<time>/ ~/sealed/
cd ~/sealed
sha256sum -c --quiet SHA256SUMS   # stop here if it fails
cd -
(umask 077; age -d -i atlas-backup.key ~/sealed/backup.tar.age | tar -x -C ~)   # ~/<date>-<time>/
rsync -rlpt ~/<date>-<time>/ <you>@<the new host>:restore/
rm -rf ~/sealed ~/<date>-<time>
```

`~/restore` on the new host is then the backup directory (`/path/to/backup` below). Keep it private: it holds every
app's API keys and logins.

## 1. The operating system

Install a 64-bit Linux server on amd64; the reference is **Ubuntu Server 24.04 LTS**. Then:

```sh
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y unattended-upgrades git nfs-common   # nfs-common only if the media is on NFS
```

Create (or keep) the user the apps run as and note its ids (`id -u`, `id -g`): they become `PUID` and `PGID`.
If the media storage already holds files owned by particular ids, use the same ones as on the old host.

## 2. Docker

Install Docker Engine and the Compose plugin from Docker's own repository, following
[docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/) (Docker Engine 25 or
later, Compose 2.27.2 or later). Add the user to the `docker` group, which is equivalent to root on the host, and
log in again:

```sh
sudo usermod -aG docker "$USER"
```

Don't install an auto-updater such as Watchtower ([installing.md](installing.md#running-it-securely)).

## 3. The media storage

Mount the storage that holds downloads and the library where `MEDIA_ROOT` will point. The apps stored
`/media/...` paths in their databases, so the **layout under `MEDIA_ROOT` must match the old host**; the host
path itself may differ. For an NFS export, a line in `/etc/fstab` such as:

```
nas.example.internal:/export/media  /srv/media  nfs4  defaults,_netdev  0  0
```

then `sudo mkdir -p /srv/media && sudo mount /srv/media`, and check that the `PUID` user can create and delete
a file there.

## 4. The repository and settings

<!-- rehearse: checkout -->
```sh
git clone https://github.com/HoneyBearTech/homelab-atlas.git
cd homelab-atlas
git checkout vX.Y.Z      # the release in the backup's VERSION, or newer; verify it (verifying-releases.md)
cp /path/to/backup/env/.env .env
chmod 600 .env
for file in autoheal.env backup.env seerr.env; do   # each one the backup has
  if [ -f "/path/to/backup/env/$file" ]; then
    cp "/path/to/backup/env/$file" "$file"
    chmod 600 "$file"
  fi
done
```

A server that follows `main` ([upgrading.md](upgrading.md#following-main)) stays on `main` here instead
(skip the `git checkout`), and gets its pull agent back once the stack is healthy.

A backup without a `VERSION` file was made by 0.3.1 or earlier, in the older archive format: check out v0.3.1 to
restore it.

The backup's `.env` has the `COMPOSE_PROFILES` it was taken with: keep it, so the restore finds the services of
every profile in the backup ([installing.md](installing.md#optional-services)); `scripts/restore.sh` refuses a
service whose profile is off, and names it. **A backup taken before the profiles has no `COMPOSE_PROFILES` in
`env/.env`**: it holds every service, so add every profile to `.env` before restoring it:

```
COMPOSE_PROFILES=4k,music,requests,logs,autoheal
```

Edit `.env` if the new host's paths differ (`MEDIA_ROOT`, `CONFIG_ROOT`, `SABNZBD_INCOMPLETE_PATH`). Older backups
made before the `CONFIG_ROOT` layout was introduced may still contain `APPDATA_ROOT` or
`RECYCLARR_CONFIG_PATH`; those legacy settings are not read by this Compose stack. Remove them, set `CONFIG_ROOT`
as in `.env.example`, and restore places each archived mount at the matching current container path, independent
of the old source path in the manifest. Never point `CONFIG_ROOT` into `/var/lib/docker/volumes`
([installing.md](installing.md#where-data-lives)). Create the host directories as the `PUID` user, so Docker doesn't
create them owned by root. The loop lists every app; leave out those whose profile is off (`radarr4k`, `sonarr4k`
and `bazarr4k` without `4k`, `lidarr` without `music`, `seerr` without `requests`, and `radarr4k/scripts` without
`4k`):

<!-- rehearse: directories -->
```sh
. ./.env
mkdir -p "$SABNZBD_INCOMPLETE_PATH" "$CONFIG_ROOT"/radarr/scripts "$CONFIG_ROOT"/radarr4k/scripts
for app in radarr radarr4k sonarr sonarr4k lidarr bazarr bazarr4k sabnzbd recyclarr seerr; do
  mkdir -p "$CONFIG_ROOT/$app/config"
done
docker compose config --quiet
docker compose pull
```

With the `logs` profile, put the Dozzle agent's certificate and key back from your password manager, owned by root,
as [installing.md](installing.md#dozzles-certificate) describes: they aren't in the backup, and without them the
restore can't create the agent's container.

## 5. Restore and start

<!-- rehearse: restore -->
```sh
scripts/restore.sh /path/to/backup    # verifies SHA256SUMS, creates the containers, asks first
docker compose up -d --wait           # waits until every service reports healthy
docker compose ps
```

Then open each app's web UI: **System → Status** should show no errors, and the root folders under `/media`
should be found. Check Recyclarr's log after its next run (`docker compose logs recyclarr`).

## What the backup doesn't bring back

- **The media itself** (`/media`) and **SABnzbd's unfinished downloads** (`/incomplete`): never backed up
  (`backup.skip`). Restore the media from your storage's snapshots or backups, if it was lost too.
- **Host settings**: firewall rules, `/etc/fstab`, a reverse proxy, monitoring agents, and the scheduled
  backup's SSH key and systemd units: set those up again as [installing.md](installing.md#scheduled-backups)
  describes, with a new key (remove the old one from the backup server).
- **The apps' posters** (`/config/MediaCover`): left out of backups; the apps download them again.
- **The Dozzle agent's certificate and key** (`CONFIG_ROOT/dozzle/certs`): never backed up; they come from your
  password manager (step 4).
- **Other machines' view of this one**: if the host's address changed, update whatever calls these apps by
  address (the indexer manager, the media server, a reverse proxy, dashboards).

## What the rehearsal covers

The "Rebuild rehearsal" workflow (`.github/workflows/rehearsal.yml`, weekly, on demand, and on pull requests that
change this page, `scripts/`, `compose.yaml` or `.env.example`) runs `scripts/rehearse-rebuild.sh` on a fresh
Ubuntu 24.04 machine; locally, `scripts/rehearse-rebuild.sh` does the same (it needs Docker, age and rsync, and
`--list` prints the steps it would run). It starts the whole stack with throwaway settings, isolated from any
installation on the same machine as the smoke test is, and takes the nightly backup (`scripts/scheduled-backup.sh`)
with an encrypted copy, in the format above, on a stand-in backup server. Then it throws the stack, its data, its
settings and the backup on the host away and follows this page from a clean clone: every fenced block right after a
`<!-- rehearse: name -->` comment (invisible on GitHub) runs in order, as a bash script that stops at the first failing
command. Such a script doesn't stop at a failing command on the left of `&&` or `||`, so the rehearsal refuses a
marked block with either: put each command on its own line, and write one that only applies sometimes as
`if [ -f ... ]; then ...; fi`. Other shapes hide a failure the same way and aren't refused, so keep them out of a
marked block too: a command as an `if` or `while` condition (other than a `[ ... ]` test), `! command`, and
`$(command)` inside another command (bash 3.2 doesn't stop at a failure there). The steps run with a home directory of the rehearsal's own (`~` is the new host's,
or the key holder's), never the caller's. It checks that every service is healthy, that each data mount holds what
was backed up, that each app kept its API key, and that the settings files are the ones backed up. A step that no
longer works fails the rehearsal, so keep the marked blocks runnable; leave a block unmarked if it only works on a
real host.

The rehearsal stands in for what only a real host has, and changes nothing else in the marked steps: the clone and the
release come from the commit under test, a local directory is the backup server, and the copy and the age key are its
own. The media storage is an empty directory, and the Dozzle agent's certificate and key come back from where it kept
them. The script's header lists each substitution.

It doesn't cover, and you check by hand on a real rebuild:

- **Installing the system and Docker** (steps 1 and 2): the rehearsal machine comes with both.
- **The NAS mount** (step 3), its `/etc/fstab` line, and that the media's layout matches the old host's.
- **The real backup server**, the SSH key and alias to reach it, and **the real age key** from your password manager.
- **Verifying the release** (`verifying-releases.md`): the rehearsal checks out the commit it tests.
- **The password manager**, for the Dozzle agent's certificate and key.
- **The apps' own screens** (System → Status, root folders), and Recyclarr's next run.
- **The pull agent** for a server that follows `main`, the scheduled backup's systemd units, and the other host
  settings listed above.
