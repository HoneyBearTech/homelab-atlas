# Pass map

What each piece of planned work shipped, newest first.

| Date | Job | What shipped | Pull request |
| --- | --- | --- | --- |
| 2026-11-20 | atlas-open-issues, #111 | ruff checks for Python 3.15, the version CI runs | [#118](https://github.com/HoneyBearTech/homelab-atlas/pull/118) |
| 2026-11-20 | atlas-open-issues, #110 | Renovate re-locks `requirements-dev.txt` with its pip-compile manager (standard header; in-place bumps off), so new tool dependencies and hashes come with the update | [#119](https://github.com/HoneyBearTech/homelab-atlas/pull/119) |
| 2026-11-20 | atlas-open-issues, #112 | The smoke test and the rebuild rehearsal share one copy of their throwaway-stack setup in `scripts/lib.sh`; behaviour unchanged | [#120](https://github.com/HoneyBearTech/homelab-atlas/pull/120) |
| 2026-11-20 | atlas-open-issues, #109 | autoheal is `ghcr.io/tmknight/docker-autoheal` 0.14.1 (Alpine 3.24, non-root, read-only) instead of `willfarrell/autoheal` (Alpine 3.18, end of life); the socket proxy also allows `GET /info`; the opt-in label is `autoheal.monitor.enable` on the 12 monitored services | [#121](https://github.com/HoneyBearTech/homelab-atlas/pull/121) |
| 2026-11-15 | trivy-triage | Triage of the 468 open image-scan alerts: 20 fixed by updates already published, 114 dismissed as not reachable (each with its reason), 334 kept open with mitigations; out-of-support .NET runtimes in Radarr, Lidarr and Sonarr recorded; roadmap items for the .NET 10 releases, port binding, memory limits and Seerr's npm update check | [#114](https://github.com/HoneyBearTech/homelab-atlas/pull/114) |
| 2026-11-15 | project goal | `agents/GOAL.md`: the project's goal as five checks (pinned images, lint and tests, Renovate, profiles, rebuild rehearsal), run on `main` by the `goal` workflow | [#107](https://github.com/HoneyBearTech/homelab-atlas/pull/107) |
| 2026-11-15 | renovate-roadmap, part 2 | Optional services as Compose profiles (`4k`, `music`, `requests`, `logs`, `autoheal`); `.env.example` turns all of them on; backup and restore refuse a missing or mistyped `COMPOSE_PROFILES`; Compose 2.27.2 or later | [#104](https://github.com/HoneyBearTech/homelab-atlas/pull/104) |
| 2026-11-15 | renovate-roadmap, part 3 | Rebuild rehearsal: `scripts/rehearse-rebuild.sh` runs the steps marked in `docs/rebuilding.md` on a fresh runner, weekly, on demand and on changes to the doc or scripts | [#105](https://github.com/HoneyBearTech/homelab-atlas/pull/105) |
| 2026-11-15 | renovate-roadmap, part 4 | Read-only trial for the linuxserver.io apps recorded in `docs/security.md`; none switched, the roadmap item stays open | [#106](https://github.com/HoneyBearTech/homelab-atlas/pull/106) |
| 2026-11-15 | renovate-roadmap, part 1 | Renovate fixes: runner labels left alone; `.pre-commit-config.yaml` tracked, its hooks pinned by SHA; the two pins of each lint tool grouped; new versions wait 3 days (image rebuilds and vulnerability fixes don't); `docs/dependencies.md` matches what Renovate does | [#103](https://github.com/HoneyBearTech/homelab-atlas/pull/103) |
