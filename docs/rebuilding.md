# Rebuilding the host

How to bring the stack back on a new or wiped machine from a backup made by `scripts/backup.sh`
([upgrading.md](upgrading.md#backing-up)), with every app's settings, history and API keys as they were. The
backup and restore scripts run end to end in CI on every change (the smoke test backs up the running stack,
changes it, restores it and checks the result).

You need: the backup directory (copied off the old host), access to the media storage, and this repository.

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
later, Compose 2.24 or later). Add the user to the `docker` group, which is equivalent to root on the host, and
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

```sh
git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
git checkout vX.Y.Z      # the release the backup was taken with, or newer; verify it (verifying-releases.md)
cp /path/to/backup/env/.env .env && chmod 600 .env
```

Edit `.env` if the new host's paths differ (`MEDIA_ROOT`, `APPDATA_ROOT`, `RECYCLARR_CONFIG_PATH`). Keep
`CONFIG_VOLUME_PREFIX`: the restore creates volumes under that prefix. Create the host directories as the
`PUID` user, so Docker doesn't create them owned by root:

```sh
. ./.env && mkdir -p "$RECYCLARR_CONFIG_PATH" "$APPDATA_ROOT"/radarr/scripts "$APPDATA_ROOT"/radarr4k/scripts
docker compose config --quiet && docker compose pull
```

## 5. Restore and start

```sh
scripts/restore.sh /path/to/backup    # verifies SHA256SUMS, creates the volumes and containers, asks first
docker compose up -d --wait           # waits until every service reports healthy
docker compose ps
```

Then open each app's web UI: **System → Status** should show no errors, and the root folders under `/media`
should be found. Check Recyclarr's log after its next run (`docker compose logs recyclarr`).

## What the backup doesn't bring back

- **The media itself**: restore it from your storage's snapshots or backups, if it was lost too.
- **Host settings**: firewall rules, `/etc/fstab`, a reverse proxy, monitoring agents.
- **Other machines' view of this one**: if the host's address changed, update whatever calls these apps by
  address (the indexer manager, the media server, a reverse proxy, dashboards).
