# Pass map

What each piece of planned work shipped, newest first.

| Date | Job | What shipped | Pull request |
| --- | --- | --- | --- |
| 2026-11-15 | trivy-triage | Triage of the 468 open image-scan alerts: 20 fixed by updates already published, 114 dismissed as not reachable (each with its reason), 334 kept open with mitigations; out-of-support .NET runtimes in Radarr, Lidarr and Sonarr recorded; roadmap items for the .NET 10 releases, port binding, memory limits and Seerr's npm update check | [#114](https://github.com/HoneyBearTech/homelab-atlas/pull/114) |
| 2026-11-15 | project goal | `agents/GOAL.md`: the project's goal as five checks (pinned images, lint and tests, Renovate, profiles, rebuild rehearsal), run on `main` by the `goal` workflow | [#107](https://github.com/HoneyBearTech/homelab-atlas/pull/107) |
| 2026-11-15 | renovate-roadmap, part 2 | Optional services as Compose profiles (`4k`, `music`, `requests`, `logs`, `autoheal`); `.env.example` turns all of them on; backup and restore refuse a missing or mistyped `COMPOSE_PROFILES`; Compose 2.27.2 or later | [#104](https://github.com/HoneyBearTech/homelab-atlas/pull/104) |
| 2026-11-15 | renovate-roadmap, part 3 | Rebuild rehearsal: `scripts/rehearse-rebuild.sh` runs the steps marked in `docs/rebuilding.md` on a fresh runner, weekly, on demand and on changes to the doc or scripts | [#105](https://github.com/HoneyBearTech/homelab-atlas/pull/105) |
| 2026-11-15 | renovate-roadmap, part 4 | Read-only trial for the linuxserver.io apps recorded in `docs/security.md`; none switched, the roadmap item stays open | [#106](https://github.com/HoneyBearTech/homelab-atlas/pull/106) |
| 2026-11-15 | renovate-roadmap, part 1 | Renovate fixes: runner labels left alone; `.pre-commit-config.yaml` tracked, its hooks pinned by SHA; the two pins of each lint tool grouped; new versions wait 3 days (image rebuilds and vulnerability fixes don't); `docs/dependencies.md` matches what Renovate does | [#103](https://github.com/HoneyBearTech/homelab-atlas/pull/103) |
