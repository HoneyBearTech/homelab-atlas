# Changelog

All notable changes to homelab-atlas are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `compose.yaml`: the Atlas stack. Radarr and Sonarr (each with a 4K instance), Lidarr, Bazarr (with a 4K
  instance), SABnzbd, FlareSolverr, Recyclarr, Dozzle and webnut, every image pinned by version tag and
  digest. Each app's config lives in a Docker volume named `<CONFIG_VOLUME_PREFIX><app>`, so existing
  volumes can be adopted; media is mounted at `/media`.
- Settings `MEDIA_ROOT`, `CONFIG_VOLUME_PREFIX` and `RECYCLARR_CONFIG_PATH`; webnut's UPS login in a gitignored
  `webnut.env` (template `webnut.env.example`).
- Backup, rollback and restore steps for the config volumes (docs/upgrading.md).

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
