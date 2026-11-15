# Decisions log

Decisions about how homelab-atlas is built and maintained, newest first. Each entry says what was decided, why,
and what was considered and rejected.

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
