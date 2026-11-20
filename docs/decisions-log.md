# Decisions log

Decisions about how homelab-atlas is built and maintained, newest first. Each entry says what was decided, why,
and what was considered and rejected.

## 2026-11-20: The four open issues (atlas-open-issues, #117)

The repo's coordinator had assigned #109 to #112 on 15 November, but no work had started; this job took them
over, one pull request each (#118 to #121).

**Decided:**

- **autoheal becomes `tmknight/docker-autoheal`.** `willfarrell/autoheal` is built on Alpine 3.18 (end of life);
  its upstream pins that base, hasn't committed since September 2025 and hasn't answered the issue asking for a
  newer base. tmknight 0.14.1 does the same job, has versioned tags and a supported base, and was proven end to
  end behind this stack's socket proxy, hardened, read-only and as user 65534. Rejected: `qmcgaw/deunhealth` (needs
  Docker's events API; no webhook, stop timeout or release since 2021); younger forks with a handful of stars.
- **The proxy also allows `GET /info`.** The new image reads it once at start and exits without it. It is
  read-only but reveals host details (kernel, OS, daemon settings); no container environment, nothing writable.
  Accepted by the owner with the plan.
- **The opt-in label changes on every monitored service** (`autoheal.monitor.enable`), as the new image requires.
  Merging recreates those containers once.
- **Renovate's pip-compile manager owns `requirements-dev.txt`.** The in-place `pip_requirements` bumps are off,
  so updates aren't proposed twice.

**Review findings:**

- Fixed: the upgrade notes and the plan said only autoheal and the proxy restart; the label change restarts every
  monitored app once.
- Fixed: `GET /info` was described only as read-only; it also reveals host details.
- Fixed: the image inventory in `dependencies.md` listed the old image as current; the row is marked as history.
- Noted, accepted: tmknight has one maintainer and its build workflow uses floating action tags; the digest pin and
  Renovate's three-day wait limit that, but don't remove it. The old image had one maintainer too.
- Noted: with pip-compile, the lock is resolved on Renovate's side; check that its first update matches CI's
  Python 3.15.
- Declined: two lines in `rehearse-rebuild.sh` over 120 characters after #112 (lint passes; style only).

## 2026-11-15: Triage of the open image-scan alerts (trivy-triage, #108)

**Decided:**

- **Dismiss only what isn't reachable.** 114 of the 468 alerts are dismissed as "won't fix", each with the reason
  in [dependencies.md](dependencies.md#current-findings) and what would make it reachable. The 334 that are
  plausibly reachable stay open, although #108 asked for every alert to be fixed or dismissed: dismissing them
  would hide a real risk.
- **Updates come through Renovate**, not hand-made pull requests: the Sonarr rebuild on 16 November and Dozzle
  v11.4.3 on 23 November (after its three-day wait).
- **Every "not reachable" reason was checked twice**, independently, against the advisory and the app's source at
  the pinned version, before anything was dismissed.
- **The six PyJWT dismissals of 7 October get corrected comments**: oauthlib does import `jwt`, on demand, for RSA
  signing; SABnzbd never reaches it.

**Accepted risk:** the .NET 8 runtime in Radarr and Lidarr (out of support since 10 November 2026) and the .NET 6
runtime in Sonarr stay until stable releases move to .NET 10. Running the prerelease lines was rejected: they are
new major versions, untested here.

**Review findings that changed the triage:** Lidarr keeps a cover's file extension, so a TIFF cover reaches
ImageSharp's TIFF encoders (12 alerts kept open, not dismissed); SABnzbd's urllib3 memory-exhaustion alert is as
reachable as Bazarr's (kept open); the mitigation list no longer claims the stack keeps the apps on the LAN, or
that a login stops flaws in the web server.

**Rejected review findings:**

- *Re-check row 6 (Sonarr's .NET 6) advisory by advisory.* The row stays open either way; the out-of-support
  runtime is the real issue.
- *T8: one Bazarr selector includes a season number.* An integer can't carry the escapes the flaw needs.
- *Narrow the table's long rows.* A Markdown table row can't be wrapped.

## 2026-11-15: The project goal as checks

**Decided:** the goal ("Keep the server's stack pinned, tested, updated automatically and rebuildable from this
repository") lives in `agents/GOAL.md` as five milestones, each proved by one command that the `goal` workflow runs
on `main`. The workflow's Actions are pinned by SHA and check out without credentials, like every other workflow.
It is not a required check: it runs after a merge, not on pull requests.

## 2026-11-15: Read-only root filesystems for the linuxserver.io apps (renovate-roadmap, part 4)

**Decided:** no app is switched. The images start with a read-only root filesystem, but their init then can't
apply `PUID`, `PGID` and `UMASK`, and the apps run as UID 911, so what they write would no longer belong to the
`PUID` user ([security.md](security.md#hardening)). The roadmap item stays open and is checked again if the images
change.

## 2026-11-15: Rebuild rehearsal (renovate-roadmap, part 3)

**Decided:**

- **A CI rehearsal counts as proof that the rebuild works**, instead of a periodic rebuild of a real machine. It runs
  the steps marked `<!-- rehearse: name -->` in `docs/rebuilding.md` verbatim, so the doc and the rehearsal can't
  drift apart.
- **Not a required check.** It runs weekly, on demand and on pull requests that touch the doc, the scripts,
  `compose.yaml` or `.env.example`; a failure there is fixed in a normal pull request.
- **Marked steps keep one command per line**, with no `&&` or `||`, so the rehearsal can run and report each one.

**Accepted risk:** what only a real host can check (the NAS mount, the real backup server and key, the apps'
screens) is not rehearsed; `docs/rebuilding.md` lists it.

## 2026-11-15: Optional services as Compose profiles (renovate-roadmap, part 2)

**Decided:**

- **Core services** (radarr, sonarr, bazarr, sabnzbd, recyclarr) have no profile. The others are grouped as `4k`,
  `music`, `requests`, `logs` and `autoheal`.
- **`.env.example` turns every profile on** (`COMPOSE_PROFILES=4k,music,requests,logs,autoheal`), so an existing
  installation keeps all its services once it adds that line.
- **The backup refuses to run** while `COMPOSE_PROFILES` is missing or names a profile that doesn't exist. Without
  that, a backup would quietly leave out the apps of the missing profiles and then rotate away the last complete
  backups. **Restore refuses** services outside the active profiles.
- **Compose 2.27.2 or later** is required, for `config --environment`.
- CI, the scans and the release build use `--profile '*'`, so every service stays tested and scanned. The smoke
  test runs twice, with every profile and with the core services only.

## 2026-11-15: Renovate check-up (renovate-roadmap, part 1)

**Decided:**

- **Runner labels stay put.** Renovate no longer updates GitHub runner labels (a rule on the `github-runners`
  datasource). The smoke test's `ubuntu-24.04` is the server's Ubuntu release and moves with the server, by hand.
  This closes #101, which proposed `ubuntu-26.04`, a label GitHub doesn't offer yet.
- **Renovate reads `.pre-commit-config.yaml`.** The hook revs are pinned by commit SHA (`# frozen: vX.Y.Z`) like every
  Action, and the actionlint image there is read by the existing regex manager.
- **Each tool's two pins are grouped** (ruff, yamllint, shellcheck-py in `requirements-dev.txt` and the hooks).
  Grouping is best-effort, so the two pins can differ for up to a week, which is harmless because CI uses
  `requirements-dev.txt`.
- **New versions wait three days after release** (`minimumReleaseAge`), then auto-merge as before. Vulnerability
  fixes skip the wait.

**Accepted risks:**

- **Image rebuilds skip the wait** (a new digest under the same tag, Docker only). Docker Hub dates a rebuild by the
  tag's last push, so a tag rebuilt about weekly would restart the clock and never pass the Monday-only schedule.
  Rebuilds are mostly base-image security refreshes, and the smoke test and the required checks still gate them. A
  moved tag on a hook or an Action still waits.
- **Version updates with no release date go through without the wait** (`minimumReleaseAgeBehaviour:
  "timestamp-optional"`). The default would hold them forever, which would silently stop those updates.

**Rejected review findings:**

- *Turn off auto-merge for pre-commit hook updates.* The hooks only run when someone runs pre-commit by hand. CI runs
  the same tools from the hash-pinned `requirements-dev.txt`. With SHA pins and the three-day wait, the remaining
  risk doesn't justify a manual merge each time.
- *The plan commit's committer is GitHub, not the automation app.* That is how a commit GitHub signs through its API
  looks; it is what makes the signature verified.

**Alternatives rejected:** keeping #101 open until GitHub ships the label. It would then have auto-merged and moved
the smoke test off the server's release.
