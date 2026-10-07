# Roadmap

Where homelab-atlas is going over roughly the next twelve months (from October 2026). Plans change; this
file changes with them, in the same pull request.

## Now: the stack in git

- Done: `compose.yaml` with Radarr and Sonarr (regular and 4K), Lidarr, Bazarr (regular and 4K), SABnzbd,
  FlareSolverr, Recyclarr and Dozzle, every image pinned by tag and digest, Dependabot proposing updates.
- Switch Atlas to run the stack from a checkout of this repository, and retire the auto-updater.
- First release (0.1.0) once Atlas runs from the repository.

## Next: safe upgrades and rebuilds

- A backup and restore script for the config volumes, tested by restoring onto a fresh host.
- Optionally move the config volumes to bind mounts under `APPDATA_ROOT`, for simpler backups.
- Health checks for each service, so `docker compose ps` shows a broken app.
- A scheduled vulnerability scan of the pinned images, reported to code scanning.
- A documented rebuild of Atlas from nothing: OS, Docker, this repository, a restored backup.

## Later

- Tighter container settings where the images allow it (read-only root filesystems, dropped capabilities).
- Optional services as Compose profiles, so a smaller installation can leave them out.

## Security and project health

- Keep CI, CodeQL, Scorecard, dependency review and the DCO check green on every change.
- Branch protection on `main` with required checks; private vulnerability reporting; secret scanning with
  push protection.
- Register for the OpenSSF Best Practices badge and reach **Passing**, then **Silver**, and meet
  **OSPS Baseline** Levels 1 and 2.
- Signed releases with checksums, SBOM and SLSA provenance from the first release on.

## What homelab-atlas will not do

- **Build or patch app images.** It runs upstream images unchanged; bugs in the apps go to their projects.
- **Configure the apps' internals** (quality profiles, indexers, download clients). Recyclarr handles
  quality settings; the rest is configured in each app and lives in its app data.
- **Store secrets.** No API keys, logins or provider credentials in the repository, encrypted or not.
- **Auto-update.** Every version change is a reviewed commit.
- **Be a general-purpose media-server distribution.** It describes one server; others are welcome to fork
  or borrow from it, but options that only another setup needs are out of scope.
- **Run the media server or the indexer manager.** Those run on other hosts.
