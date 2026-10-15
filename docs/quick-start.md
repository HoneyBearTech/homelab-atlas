# Quick start

You need a Linux host (the reference is Ubuntu 24.04) with Docker Engine and the Compose v2 plugin, a user in
the `docker` group, and one directory (or mounted share) that holds both downloads and the media library.

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
   ```

   Check out the latest release (`git checkout vX.Y.Z`, from the repository's Releases page) and verify it first
   ([verifying-releases.md](verifying-releases.md)).

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   In `.env`, set `PUID`/`PGID` to the user that owns your media, `TZ`, `MEDIA_ROOT` (downloads and media),
   `SABNZBD_INCOMPLETE_PATH` (SABnzbd's unfinished downloads) and `CONFIG_ROOT`, which holds one folder per app
   (`<app>/config`: its settings, API key and database; Radarr's custom scripts in `<app>/scripts`). Never point a
   setting into `/var/lib/docker/volumes`: `docker volume prune` can delete what's there
   ([installing.md](installing.md#where-data-lives)). Every setting is described in
   [interfaces.md](interfaces.md#settings).

3. **Create the host directories** as that user, so Docker doesn't create them owned by root:

   ```sh
   . ./.env && mkdir -p "$MEDIA_ROOT" "$SABNZBD_INCOMPLETE_PATH" \
     "$CONFIG_ROOT"/radarr/scripts "$CONFIG_ROOT"/radarr4k/scripts
   for app in radarr radarr4k sonarr sonarr4k lidarr bazarr bazarr4k sabnzbd recyclarr; do
     mkdir -p "$CONFIG_ROOT/$app/config"
   done
   ```

4. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your settings
   docker compose up -d
   docker compose ps
   ```

5. **Finish each app's setup in its web UI** (ports in [interfaces.md](interfaces.md#ports)): turn on
   authentication first, then add the download client, root folders under `/media`, and indexers. Recyclarr
   creates a starter `recyclarr.yml` in `CONFIG_ROOT/recyclarr/config`; add your Radarr and Sonarr URLs and API keys
   there.

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
