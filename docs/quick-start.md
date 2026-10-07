# Quick start

You need a Linux host (the reference is Ubuntu 24.04) with Docker Engine and the Compose v2 plugin, a user in
the `docker` group, and one directory (or mounted share) that holds both downloads and the media library.

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
   ```

   Once releases exist, check out the latest one (`git checkout vX.Y.Z`) and verify it first
   ([verifying-releases.md](verifying-releases.md)).

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   In `.env`, set `PUID`/`PGID` to the user that owns your media, `TZ`, `MEDIA_ROOT` (downloads and media),
   `APPDATA_ROOT` and `RECYCLARR_CONFIG_PATH`. `CONFIG_VOLUME_PREFIX` names the Docker volumes that hold each
   app's settings; keep the default for a new installation. Every setting is described in
   [interfaces.md](interfaces.md#settings).

3. **Create the host directories** as that user, so Docker doesn't create them owned by root:

   ```sh
   . ./.env && mkdir -p "$MEDIA_ROOT" "$RECYCLARR_CONFIG_PATH" "$APPDATA_ROOT"/radarr/scripts "$APPDATA_ROOT"/radarr4k/scripts
   ```

4. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your settings
   docker compose up -d
   docker compose ps
   ```

5. **Finish each app's setup in its web UI** (ports in [interfaces.md](interfaces.md#ports)): turn on
   authentication first, then add the download client, root folders under `/media`, and indexers. Recyclarr
   creates a starter `recyclarr.yml` in `RECYCLARR_CONFIG_PATH`; add your Radarr and Sonarr URLs and API keys
   there.

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
