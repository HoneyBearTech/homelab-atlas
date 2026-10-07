# Changelog

All notable changes to homelab-atlas are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/HoneyBearTech/homelab-atlas/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HoneyBearTech/homelab-atlas/releases/tag/v0.1.0
