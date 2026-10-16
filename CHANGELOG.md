# Changelog

All notable changes to homelab-atlas are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Upgrading

- **Move each app's config into its config directory before deploying this**, and **add `CONFIG_ROOT` to `.env`**
  (required; see `.env.example`). With each app stopped, copy the contents of its config volume
  (`<CONFIG_VOLUME_PREFIX><app>`; Sonarr 4K's `SONARR4K_CONFIG_VOLUME` if you set it) into
  `<CONFIG_ROOT>/<app>/config`, owned by `PUID:PGID`, for radarr, radarr4k, sonarr, sonarr4k, lidarr, bazarr,
  bazarr4k and sabnzbd, and leave the app stopped until this is deployed (what it writes to the volume after the
  copy is lost). For Radarr, for example:

  ```sh
  docker compose stop radarr
  . ./.env && docker run --rm --network none -v "${CONFIG_VOLUME_PREFIX}radarr:/from:ro" \
    -v "$CONFIG_ROOT/radarr/config:/to" busybox cp -a /from/. /to/
  ```

  `cp -a` keeps the files' owners. The old volumes aren't touched: remove them (`docker volume rm`) once the apps
  run from the directories, and drop `CONFIG_VOLUME_PREFIX` and `SONARR4K_CONFIG_VOLUME` from `.env` (they're no
  longer read). A deploy without `CONFIG_ROOT` stops at `docker compose config` and changes nothing.
- Backups taken while the config was in volumes (0.4.0 and later) restore as they are: `scripts/restore.sh` puts
  each app's archive into its config directory.
- **Move Recyclarr's config and Radarr's scripts under `CONFIG_ROOT` before deploying this.** With the app stopped,
  move the contents of each old folder into its new one, owned by `PUID:PGID`:

  | App | Old location | New location |
  | --- | --- | --- |
  | recyclarr | `RECYCLARR_CONFIG_PATH` | `CONFIG_ROOT/recyclarr/config` |
  | radarr | `APPDATA_ROOT/radarr/scripts` | `CONFIG_ROOT/radarr/scripts` |
  | radarr4k | `APPDATA_ROOT/radarr4k/scripts` | `CONFIG_ROOT/radarr4k/scripts` |

  For Recyclarr, for example:

  ```sh
  docker compose stop recyclarr
  . ./.env && mkdir -p "$CONFIG_ROOT/recyclarr/config" &&
    cp -a "$RECYCLARR_CONFIG_PATH/." "$CONFIG_ROOT/recyclarr/config/"
  ```

  Then drop `RECYCLARR_CONFIG_PATH` and `APPDATA_ROOT` from `.env` (they're no longer read), and remove the old
  folders once the apps run from the new ones. `CONFIG_ROOT` must be in `.env` before deploying (see above): a
  deploy without it stops at `docker compose config` and changes nothing. Never put `CONFIG_ROOT` inside
  `/var/lib/docker/volumes` ([docs/installing.md](docs/installing.md#where-data-lives)). Backups taken before this
  restore as they are: `scripts/restore.sh` puts Recyclarr's and Radarr's archives into the new folders.

### Added

- `scripts/backup.sh` and `scripts/restore.sh` take the pull agent's deploy lock before they stop or create anything,
  and hold it until they exit, so a deploy can't start a service a backup has stopped or recreate one in the middle
  of a restore. The agent skips its runs meanwhile and catches up afterwards. A deploy in progress is waited for (up
  to 30 minutes, then the script fails without changing anything). On a host without the agent (no
  `homelab-pull/atlas` state directory) nothing changes ([docs/upgrading.md](docs/upgrading.md#following-main)).

### Changed

- Every app's own data now lives in one folder per app under `CONFIG_ROOT`, the same layout as the other homelab
  stacks: Recyclarr's config moves to `CONFIG_ROOT/recyclarr/config` and Radarr's and Radarr 4K's custom scripts to
  `CONFIG_ROOT/<app>/scripts` (the maintainer's decision, 2026-10-15), so the settings `RECYCLARR_CONFIG_PATH` and
  `APPDATA_ROOT` are gone. The docs now warn never to point a path setting into `/var/lib/docker/volumes` or keep app
  data in named volumes: `docker volume prune` deletes a volume no container mounts as one, even one whose `_data`
  folder a service bind-mounts ([docs/installing.md](docs/installing.md#where-data-lives)).
- Each app's config (settings, API key and database) moves from a Docker volume to a config directory on the host,
  `CONFIG_ROOT/<app>/config`, still mounted at `/config` (the maintainer's decision, 2026-10-14). The new required
  setting `CONFIG_ROOT` replaces `CONFIG_VOLUME_PREFIX` and `SONARR4K_CONFIG_VOLUME`, and `compose.yaml` no longer
  declares any volumes. `scripts/restore.sh` writes each archive to what the service mounts at that container path
  now, creating a missing directory and recreating a container that predates `compose.yaml`, so backups of the old
  volumes restore into the new directories ([docs/installing.md](docs/installing.md#where-data-lives)).
- Docs: the maintainer's server now follows `main` with a pull agent instead of running a release tag, so a merge
  deploys within about two minutes, Dependabot's automatic merges included. Rollback is a revert pull request; a
  server is held on a version by checking out that commit, which pauses the agent. Release tags stay as signed,
  verified snapshots ([docs/upgrading.md](docs/upgrading.md#following-main)).
- Dependabot's major updates now merge automatically too, once every required check passes (the maintainer's
  decision, 2026-10-14), so they deploy unattended with the nightly backup behind them; a revert doesn't undo a
  data migration, so that backup is the way back. An update Dependabot can't classify still waits for the
  maintainer ([docs/dependencies.md](docs/dependencies.md#tracking-dependencies)).

### Fixed

- `scripts/backup.sh` no longer leaves a service down when stopping it fails. A process that can't exit in time
  (stuck writing to a network share) made the stop fail while its container was still on its way down; the backup
  gave up, started the services again at once (Compose skipped the container, which still ran) and the service stayed
  stopped once it exited, as `restart: unless-stopped` doesn't restart after a stop. The rest of the backup and the
  copy off the host were never made. Now the backup waits up to `BACKUP_STOP_WAIT` seconds (default 120) for the
  container to exit and carries on; if it still runs then, the backup fails and waits once more before starting
  anything. Every service that was running when the backup began must be running again at the end, or the backup
  fails and names it (the scheduled backup reports that to the push monitor).
- SABnzbd gets a minute to stop (`stop_grace_period: 1m`) instead of Docker's 10 s, so it can finish writing to
  `/incomplete` and exit cleanly rather than be killed in the middle of a write. Deploying this recreates its
  container.

## [0.4.0] - 2026-10-14

The backup scripts, smoke test and CI now follow homelab-ares, the template for the homelab stacks. A backup holds
the same data as before, in a new layout.

### Added

- Label `org.honeybeartech.atlas.backup.skip`: container paths a backup never archives and a restore refuses to
  write. Every app that mounts the media library carries `/media`, and SABnzbd also `/incomplete`.
- Every backup also records `NETWORKS` (the address range of each network the stack uses but doesn't create; none
  today) and `VERSION` (the release it was taken with).
- CI logs in to Docker Hub with a read-only token when the repository has one (pulls stay anonymous until then), and
  logs out before the smoke test starts any container. A `.gitlab-ci.yml` for a GitLab mirror of the repository
  (inactive until that mirror is set up).

### Changed

- `scripts/backup.sh` archives every read-write volume or bind mount of every service except the Docker socket,
  anonymous volumes and the mounts in its `backup.skip` label, instead of a fixed list of `/config` and `/scripts`.
  With the new labels that is exactly what it archived before: the apps' `/config`, Recyclarr's `/config` and
  Radarr's `/scripts`, never `/media` or `/incomplete`. A mount inside another mount is archived on its own.
- Archives are named `<service>--<path>.tar.gz` (such as `radarr--config.tar.gz`, was `radarr-config.tar.gz`), and
  the `MANIFEST` is tab-separated with the archive's name in its first column. `scripts/restore.sh` restores what
  the `MANIFEST` lists, and refuses a skipped mount.
- `org.honeybeartech.atlas.backup.exclude` takes comma-separated paths at any depth inside a data mount (it was
  entries directly inside `/config` or `/scripts`, separated by spaces). The apps' `/config/MediaCover` stays as it
  is. A path outside every data mount, or with `..` or a pattern character, still fails the backup and the restore
  before anything stops.
- The smoke test derives its throwaway settings from `.env.example` (every `*_ROOT` and `*_PATH` a temporary
  directory owned by `PUID:PGID` with mode 0755 as on a host, `*_PREFIX`, `*_VOLUME` and `*_NETWORK` names of its
  own, so never the real `SONARR4K_CONFIG_VOLUME`), and checks that skipped mounts and excluded paths are neither
  archived nor overwritten, and that every backup has a `NETWORKS` file. It still never reads `.env` or
  `autoheal.env`.
- The smoke test runs on `ubuntu-24.04` (amd64) instead of `ubuntu-latest`.

### Security

- Every service drops every Linux capability (`cap_drop: [ALL]`) and runs with `no-new-privileges`. The
  linuxserver.io apps add back only `CHOWN`, `DAC_OVERRIDE`, `SETUID`, `SETGID` and `KILL`, which their init needs
  to take ownership of `/config`, start the app as `PUID:PGID` and stop it cleanly; every other service runs with
  none. recyclarr, dozzle and autoheal now have a read-only root filesystem too (socket-proxy already had one;
  recyclarr and dozzle get `/tmp` in memory). The table is in docs/security.md#hardening.
- The policy check enforces it: new rules `no-new-privileges` and `cap-drop`, `cap-add` now fails only on a
  capability outside Docker's default set, and a new rule `devices` refuses host devices mapped into a container.

### Upgrading

- **Backups made before this version can only be restored with the previous release's `scripts/restore.sh`**
  (v0.3.1): check out that tag to restore one. Such a backup has no `VERSION` file; the new `restore.sh` refuses it
  without changing anything. Backups made from now on use the new format.
- Nothing to change in `.env`, and the systemd units are the same as in 0.3.x (they already use the best-effort
  I/O class), so they don't need re-installing.
- Data whose files have unexpected owners can fail with "permission denied" (`EACCES`) after the upgrade: a service
  that runs without capabilities can only reach what it owns. The linuxserver.io apps still take ownership of
  `/config` as they start. Recyclarr runs as `PUID:PGID` with no capabilities, so `RECYCLARR_CONFIG_PATH` must
  belong to that user, as it should already.

## [0.3.1] - 2026-10-13

Two settings the stack needs to take over Atlas as it runs today.

### Upgrading

- **Set `SABNZBD_INCOMPLETE_PATH`** in `.env` (required): the host directory SABnzbd uses as its temporary download
  folder, mounted at `/incomplete`. Point it at wherever SABnzbd assembles downloads now (its *Temporary Download
  Folder* setting).
- **Sonarr 4K moves to port 8988**: point Recyclarr, the indexer manager and anything else using 8888 at 8988. If
  its config volume doesn't follow `CONFIG_VOLUME_PREFIX`, name it with `SONARR4K_CONFIG_VOLUME`.

### Changed

- SABnzbd mounts `SABNZBD_INCOMPLETE_PATH` (a new, required setting) at `/incomplete`, its temporary download folder,
  which can be on another disk or share than `MEDIA_ROOT`.
- Sonarr 4K is published on port 8988 (was 8888), and its config volume can have a name of its own
  (`SONARR4K_CONFIG_VOLUME`, optional; default `<CONFIG_VOLUME_PREFIX>sonarr4k`).

## [0.3.0] - 2026-10-13

Nightly backups copied off the host, Dependabot updates for the linuxserver.io images, and Dozzle as an agent of a
central Dozzle hub.

### Upgrading

- **Dozzle has no web UI on this host any more.** It runs as an agent on port 7007 for a Dozzle hub on another host
  (the hub lists this host as `<address>:7007`). Point anything that linked to port 4040 at the hub instead.
- **Scheduled backups are optional** and need setting up once: a backup server, an SSH key, `backup.env` and the
  systemd units, as [docs/installing.md](docs/installing.md#scheduled-backups) describes. Without them nothing
  changes: `scripts/backup.sh` still works by hand.
- The app images are the same app versions as 0.2.0 (rebuilt base packages only), so no database migrates. Take a
  backup first as usual ([docs/upgrading.md](docs/upgrading.md)); it now stops each app only while its own data is
  copied.

### Added

- Scheduled backups: `scripts/scheduled-backup.sh` takes a backup, copies it to another machine with rsync
  (`SHA256SUMS` last, so a cut-off copy is refused by the restore), keeps the newest 3 here and 30 there, and
  reports to an Uptime Kuma push monitor. Settings in the optional, gitignored `backup.env`
  (`backup.env.example`); systemd user units in `deploy/systemd/` run it nightly at 03:00
  ([docs/installing.md](docs/installing.md#scheduled-backups)).
- A service's `org.honeybeartech.atlas.backup.exclude` label lists entries in its `/config` or `/scripts` that
  backups leave out and restores keep. Radarr, Sonarr (both instances) and Lidarr leave out their posters
  (`/config/MediaCover`), which they download again.

### Changed

- `scripts/backup.sh` stops each service only while its own data is copied, and compresses after it has started
  again (with pigz when it's installed), instead of stopping the whole stack for the whole backup.
- Dozzle runs as an agent (`dozzle agent`, port 7007) for the homelab's Dozzle hub on another host, which shows
  every host's logs in one web UI, and moves to 11.3.2, the hub's version. Atlas no longer has a Dozzle web UI of
  its own on port 4040.
- Radarr and Radarr 4K, Sonarr and Sonarr 4K, Lidarr, SABnzbd and socket-proxy move to linuxserver.io's newest
  builds of the same app versions: rebuilt base packages, no database migration.
- linuxserver.io images are pinned by their `version-<app version>` tag (socket-proxy by its bare version)
  instead of the `-lsNNN` build tag, which Dependabot can't follow. Dependabot now proposes their new versions
  and rebuilds; a rebuild (same tag, new digest, nothing else changed) is merged automatically once the checks
  pass, like patch and minor updates.
- Dependabot checks for updates every Monday at 06:00 UTC.

## [0.2.0] - 2026-10-07

autoheal: a service whose health check fails is restarted automatically, through a socket proxy that can only
list, restart and stop containers.

### Upgrading

- Two new services, `autoheal` and `socket-proxy`, start with the rest (`docker compose up -d`); they need no
  settings. For restart notices, create `autoheal.env` from `autoheal.env.example` (mode `600`) with a webhook
  URL; without it, restarts are only logged.
- Take a backup first as usual ([docs/upgrading.md](docs/upgrading.md)); no app version changes in this release.

### Added

- autoheal restarts any service whose health check fails (every app, Dozzle, Recyclarr and the proxy carry the
  `autoheal: "true"` label), and can post each restart to a webhook such as a Discord channel (`WEBHOOK_URL` in
  the optional, gitignored `autoheal.env`). It reaches Docker only through `socket-proxy`, which allows listing,
  inspecting, restarting and stopping containers and nothing else, on an internal network with no published
  port. Both are labelled policy exceptions (`latest` for autoheal, whose only maintained tag it is;
  `docker-socket` for the proxy).
- The smoke test makes a container unhealthy and checks that autoheal restarts it, and retries the stack's start
  once when a service fails for a network reason (Recyclarr's first fetch from GitHub).
- `scripts/backup.sh` also backs up `autoheal.env`.

### Changed

- The health checks' start period is 10 minutes (was 3), so autoheal can't restart an app in the middle of a
  slow database migration after an upgrade; a healthy app is still reported within seconds.

## [0.1.0] - 2026-10-07

The first release: the Atlas stack as a Compose file, every image pinned by version tag and digest, with the
checks, backups and release signing around it.

### Added

- `compose.yaml` with 10 services: Radarr 6.4.4 and Sonarr 4.0.20 (each with a 4K instance), Lidarr 3.1.0,
  Bazarr 1.6.2 (with a 4K instance), SABnzbd 5.1.3, Recyclarr 8.7.3 and Dozzle 11.3.0. Each app's config
  lives in a Docker volume named `<CONFIG_VOLUME_PREFIX><app>`, so an existing installation's volumes can be
  adopted; media is mounted at `/media` from `MEDIA_ROOT`.
- A health check for every service, so `docker compose ps` and `docker compose up --wait` show a broken app.
  Needs Docker Engine 25 and Compose 2.24 or later.
- `.env.example` listing every setting the stack reads; no secrets go in it.
- `scripts/backup.sh` and `scripts/restore.sh`: back up every service's `/config` and `/scripts` mount and
  `.env` with a manifest and checksums (readable only by the user who ran it), and restore them after
  verifying the checksums and asking first. [docs/rebuilding.md](docs/rebuilding.md) brings the stack back on
  a new host from a backup.
- `scripts/check_compose.py`: the stack's policy check (every image pinned as `name:tag@sha256:<digest>`, no
  `latest`, no build, nothing privileged, no added capabilities, host network or PID namespace, no Docker
  socket mount, a health check on every service, unless a service's `org.honeybeartech.atlas.allow.<rule>`
  label gives the reason), and the CycloneDX SBOM of the images attached to each release.
- CI on every change: ruff, yamllint, shellcheck, actionlint, gitleaks over the whole history, the checker's
  tests (90 % branch-coverage floor), the policy check, and a smoke test that starts the whole stack, waits
  until every service is healthy, then backs it up, changes it, restores it and checks the result. CodeQL,
  OpenSSF Scorecard, dependency review and a DCO check also run.
- Dependabot for the images, the Python tools and the Actions; patch and minor updates merge automatically
  once every required check passes, major updates wait for the maintainer.
- A weekly vulnerability scan of every pinned image (Trivy), reported to code scanning.
- Releases (this one first) carry a source archive, the SBOM, `SHA256SUMS` signed keylessly with cosign, and
  SLSA build provenance ([docs/verifying-releases.md](docs/verifying-releases.md)).
- Project policies (`SECURITY.md`, `CONTRIBUTING.md`, `GOVERNANCE.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`)
  and docs: quick start, installing, upgrading, rebuilding, architecture, interfaces, security requirements,
  assurance case, dependencies and roadmap.

### Security

- Known vulnerabilities at release: 155 open findings from the image scan, all in upstream images with no
  fixed build yet (the .NET runtimes bundled into Radarr, Lidarr and Sonarr; Python packages in SABnzbd and
  Bazarr), none reachable from the internet. Triage and mitigations:
  [docs/dependencies.md](docs/dependencies.md#current-findings).

[Unreleased]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HoneyBearTech/homelab-atlas/releases/tag/v0.1.0
