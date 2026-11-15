# Roadmap

Where homelab-atlas is going over roughly the next twelve months (from October 2026). Plans change; this
file changes with them, in the same pull request.

## Done: the stack in git

- Done: `compose.yaml` with Radarr and Sonarr (regular and 4K), Lidarr, Bazarr (regular and 4K), SABnzbd,
  Recyclarr, Seerr, Dozzle, autoheal and socket-proxy, every image pinned by tag and digest; Renovate proposes
  image, tool and Action updates and image rebuilds.
- Done: a health check for each service, so `docker compose ps` shows a broken app, and a smoke test in CI that
  starts the whole stack and waits until every service is healthy.
- Done: a weekly vulnerability scan of every pinned image (Trivy), reported to code scanning.
- Done: autoheal restarts any app whose health check fails, through a socket proxy that only allows listing,
  restarting and stopping containers.
- Done: backup and restore scripts, exercised end to end by the smoke test in CI, and a documented rebuild of
  the host from a backup.
- Done: a nightly backup copied to another machine, with retention and a push monitor
  ([installing.md](installing.md#scheduled-backups)).
- Done: every service drops all Linux capabilities and can't gain new privileges; the linuxserver.io apps add back
  only what their init needs, and every other service has a read-only root filesystem
  ([security.md](security.md#hardening)).
- Done: a first signed, verified release (0.1.0) before Atlas switched over.
- Done: Atlas runs the stack from a checkout of this repository, following `main` with a pull agent that deploys
  each merge ([upgrading.md](upgrading.md#following-main)); the auto-updater is retired.

## Now: safe upgrades and rebuilds

- Done: each app's config in a directory on the host (`CONFIG_ROOT`) instead of a Docker volume, for simpler
  backups and rebuilds.
- Done: backups and restores hold off the pull agent's deploys while they run.
- Done: the documented rebuild is rehearsed in CI on a fresh runner every week and on every change to it
  ([rebuilding.md](rebuilding.md#what-the-rehearsal-covers)); only the NAS mount, the real backup server, the
  password manager and the apps' own screens still need a real host.

## Later

- Read-only root filesystems for the linuxserver.io apps, if their images ever allow it. Checked November 2026:
  they start read-only, but then ignore `PUID`, `PGID` and `UMASK` ([security.md](security.md#hardening)).
- Done: optional services as Compose profiles (`4k`, `music`, `requests`, `logs`, `autoheal`), so a smaller
  installation can leave them out ([installing.md](installing.md)); the backup refuses to run while
  `COMPOSE_PROFILES` is missing or mistyped.

## Security and project health

- Keep CI, CodeQL, Scorecard, dependency review and the DCO check green on every change.
- Branch protection on `main` with required checks; private vulnerability reporting; secret scanning with
  push protection.
- Keep the OpenSSF Best Practices **Silver** badge (Passing and Silver reached in October 2026) and
  **OSPS Baseline** Levels 1 and 2 (met).
- Signed releases with checksums, SBOM and SLSA provenance, as every release so far has had.
- Move Radarr and Sonarr to their .NET 10 releases (Radarr 7, Sonarr 5) once those are stable: Radarr bundles
  .NET 8, out of support since 10 November 2026, and Sonarr .NET 6, out of support since November 2024. Watch for
  a Lidarr release that does the same; checked November 2026, it has none
  ([dependencies.md](dependencies.md#current-findings)).
- Dismiss the ImageSharp TIFF decoder alerts once a stable Radarr, Sonarr and Lidarr release restricts ImageSharp's
  decoders (upstream's fix, so far only in their prereleases); until then they stay open
  ([dependencies.md](dependencies.md#current-findings)).

## What homelab-atlas will not do

- **Build or patch app images.** It runs upstream images unchanged; bugs in the apps go to their projects.
- **Configure the apps' internals** (quality profiles, indexers, download clients). Recyclarr handles
  quality settings; the rest is configured in each app and lives in its app data.
- **Store secrets.** No API keys, logins or provider credentials in the repository, encrypted or not.
- **Auto-update from registries.** Every version change is a commit in `main` that passed CI; the server applies
  only those.
- **Be a general-purpose media-server distribution.** It describes one server; others are welcome to fork
  or borrow from it, but options that only another setup needs are out of scope.
- **Run the media server or the indexer manager.** Those run on other hosts.
