# Quick start

> **Planned.** `compose.yaml` doesn't exist yet: the services are being moved into this repository from
> the server they run on today ([roadmap](roadmap.md)). These steps are how it will work.

You need a Linux host (the reference is Ubuntu 24.04) with Docker Engine and the Compose v2 plugin, and a
user in the `docker` group.

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
   git checkout v0.1.0   # the latest release; see docs/verifying-releases.md to check it first
   ```

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   Set `PUID`/`PGID` to the user that should own the files, `TZ`, and the two host directories:
   `APPDATA_ROOT` (each app's config and database) and `DATA_ROOT` (downloads and media). Every setting is
   described in [interfaces.md](interfaces.md#settings-env).

3. **Create the directories** as that user, so Docker doesn't create them owned by root:

   ```sh
   . ./.env && mkdir -p "$APPDATA_ROOT" "$DATA_ROOT"
   ```

4. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your .env
   docker compose up -d
   docker compose ps
   ```

5. **Finish each app's setup in its web UI** (ports in [interfaces.md](interfaces.md#ports)): turn on
   authentication first, then add the download client, root folders under `/data`, and indexers.

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
