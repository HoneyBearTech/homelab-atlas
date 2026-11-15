# Decisions log

Decisions about how homelab-atlas is built and maintained, newest first. Each entry says what was decided, why,
and what was considered and rejected.

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
