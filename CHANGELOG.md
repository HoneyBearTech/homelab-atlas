# Changelog

All notable changes to homelab-atlas are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Security

- Triaged the first image scan (docs/dependencies.md#current-findings): Bazarr updated to `v1.6.2-ls367` and
  Recyclarr to `8.7.3`, which fix 17 findings. FlareSolverr was removed from the stack: nothing used it, and
  its Chromium carried most of the findings (348), the only ones reachable from the internet.

### Added

- `scripts/backup.sh`: stops the stack, archives every service's `/config` and `/scripts` mount and `.env`
  with a manifest and checksums (readable only by the user who ran it), then starts what was running.
- `scripts/restore.sh`: verifies a backup, creates missing containers and volumes, and after confirmation
  replaces the services' `/config` and `/scripts` contents, keeping owners and modes. The smoke test now runs a
  backup, a change and a restore, and checks that the data and every service's health came back.
- `docs/rebuilding.md`: bringing the stack back on a new or wiped host from a backup.
- A weekly vulnerability scan of every pinned image (`scan.yml`: Trivy, HIGH and CRITICAL findings with a fix
  available, for linux/amd64), also run when `compose.yaml` changes on `main`. Findings go to code scanning,
  one category per image.
- A health check for every service (each app's own status endpoint; Recyclarr's scheduler; Dozzle's built-in
  check), so `docker compose ps` and `docker compose up --wait` show a broken app. Needs Docker Engine 25 and
  Compose 2.24 or later.
- The policy check's `healthcheck` rule: every service must define a health check.
- `scripts/smoke-test.sh` (`make smoke`), run in CI as "Stack smoke test": starts every service with throwaway
  settings, isolated from any existing installation, and fails unless each one is healthy within five minutes.
- shellcheck for the scripts, in `make lint` and CI.

- `compose.yaml`: the Atlas stack. Radarr and Sonarr (each with a 4K instance), Lidarr, Bazarr (with a 4K
  instance), SABnzbd, Recyclarr and Dozzle, every image pinned by version tag and
  digest. Each app's config lives in a Docker volume named `<CONFIG_VOLUME_PREFIX><app>`, so existing
  volumes can be adopted; media is mounted at `/media`.
- Settings `MEDIA_ROOT`, `CONFIG_VOLUME_PREFIX` and `RECYCLARR_CONFIG_PATH`.
- Backup, rollback and restore steps for the config volumes (docs/upgrading.md).
- Dependabot's patch and minor updates are merged automatically once every required check passes
  (`dependabot-auto-merge.yml`); major updates still wait for the maintainer.

- `scripts/check_compose.py`: checks the resolved Compose file against the stack's policy (every image
  pinned as `name:tag@sha256:<digest>`, no `latest`, no build, nothing privileged, no added capabilities,
  host network or PID namespace, no Docker socket mount, unless a service's
  `org.honeybeartech.atlas.allow.<rule>` label gives the reason) and writes a CycloneDX SBOM of the images
  for releases. Tests with a 90 % branch-coverage floor.
- `.env.example` listing every setting the stack reads.
- Project policies (`SECURITY.md`, `CONTRIBUTING.md`, `GOVERNANCE.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`)
  and docs: quick start, installing, upgrading, architecture, interfaces, security requirements, assurance
  case, dependencies, roadmap and verifying releases. What isn't built yet is marked "Planned".
- CI (ruff, yamllint, actionlint, gitleaks over the history, tests with coverage, the Compose policy check),
  CodeQL, OpenSSF Scorecard, dependency review, a DCO check, Dependabot, and a release workflow that signs
  checksums keylessly and attaches the SBOM and SLSA provenance.

[Unreleased]: https://github.com/HoneyBearTech/homelab-atlas/commits/main
