# Plan: Renovate check-up and the open roadmap items

## What Sean asked for

"Make sure that Renovate is set up properly on this repo and that all roadmap items are completed."

## What we found

- Renovate works: it found every dependency it was meant to, and its pull requests #90-#100 merged within minutes
  with every required check green. Its config passes `renovate-config-validator --strict`.
- One Renovate pull request is stuck: #101 moves the smoke test to an `ubuntu-26.04` runner, a label GitHub doesn't
  offer yet, so actionlint fails "Checks + tests". The smoke test is pinned to 24.04 on purpose (#28): it runs on the
  same release as the server. Even once GitHub ships the label, Renovate would merge it on its own and move the test
  off the server's release.
- Gaps: Renovate doesn't read `.pre-commit-config.yaml`, so its pins drift (ruff there is 0.17.4, while
  `requirements-dev.txt` has 0.17.5). `docs/dependencies.md` still says autoheal and busybox are bumped by hand
  (Renovate does both), names the wrong file for busybox, and leaves out `.gitlab-ci.yml`. Updates merge as soon as
  they are published, with no waiting period.
- Roadmap: three items are open. "Optional services as Compose profiles" and "Rehearse the documented rebuild" can be
  done in this repo. "Read-only root filesystems for the linuxserver.io apps" depends on the images; we test it again
  and record the result.

## What we'll change

Four pull requests, each reviewed and approved on its own.

1. **Renovate fixes** (this pull request, after the plan is approved)
   - `.github/renovate.json5`:
     - a rule that turns off runner-label updates (`github-runners`). The runner moves with the server, by hand.
     - the `pre-commit` manager, so `.pre-commit-config.yaml` is kept current. The actionlint image there is read
       by the existing regex.
     - `minimumReleaseAge: "3 days"`. Every update waits three days after release, then auto-merges as today;
       security fixes from vulnerability alerts skip the wait.
   - `.pre-commit-config.yaml`: ruff to match `requirements-dev.txt`.
   - `docs/dependencies.md`, the comments in `scripts/lib.sh` and the smoke-test comment in `ci.yml`, so they match
     what Renovate does and why the runner is pinned. This is a comment-only change to `ci.yml`.
   - Close #101 once the rule is merged.
   - Checked by: the config validator in strict mode; a local Renovate extract run that shows the pre-commit pins and no
     runner label; `make lint test`; CI.
2. **Optional services as Compose profiles**
   - Radarr, Sonarr, Bazarr, SABnzbd and Recyclarr always run.
   - Optional groups:
     - `4k`: Radarr 4K, Sonarr 4K, Bazarr 4K.
     - `music`: Lidarr.
     - `requests`: Seerr.
     - `logs`: Dozzle.
     - `autoheal`: autoheal with its socket proxy.
   - `.env.example` turns on every group by default, so a new installation still gets the whole stack.
   - Everything that lists the images uses every group, so nothing goes unscanned or unpinned: the policy check, the
     image pre-pull, the Trivy scan, the release SBOM and `make check`.
   - Backup and restore follow the active groups, and the docs say to restore with the same groups.
   - The smoke test runs twice in the same required job: all groups, then core only.
   - New tests check which services carry which group.
   - Updated docs: installing, rebuilding, interfaces, architecture, security, README, CHANGELOG.
   - **Before merging:** Sean adds one line to the server's private `.env`, which we hand him. Without it the
     optional apps would stop being managed by deploys. The merge waits until he says it's in.
   - Checked by: `make lint test check smoke`, both smoke-test runs in CI, and a check that every image still appears
     in the scan list and the SBOM.
3. **Automated rebuild rehearsal**
   - A new workflow, not a required check, runs weekly, on demand, and on pull requests that change the rebuild doc or
     the backup scripts.
   - Steps on a fresh GitHub runner:
     1. Start the stack.
     2. Take a backup in the documented format (encrypted, with checksums).
     3. Throw the stack and its config away.
     4. Follow `docs/rebuilding.md` from a clean checkout: restore, start, and wait until every service is healthy.
   - The commands it runs come from the rebuild doc itself, so the doc can't drift from what works.
   - The roadmap item is marked done, with what only a real host can test: the NAS mount, the real backup server,
     the apps' own screens.
   - Checked by: the workflow passing on its pull request, and failing when a step in the doc is broken on purpose
     (tried locally, not committed).
4. **Read-only root filesystems for the linuxserver.io apps**
   - Try each linuxserver.io app with a read-only root filesystem in the smoke test.
   - Adopt it for any app whose image now supports it. Record the result for the rest in `docs/security.md`, and keep
     the roadmap line open for those.
   - Checked by: the smoke test in CI with the change.
   - This one goes after the profiles pull request, because both change `compose.yaml`.

Finally, `docs/roadmap.md` and the repo's job notes are updated as each piece ships.

## Who's on it

Researcher (done), Engineers (one per pull request), QA, Security Officer, Auditor.

## Risks

- Merging deploys to the server within about two minutes. Pull requests 2 and 4 recreate containers, so the apps
  restart. Merge them one at a time, after the nightly backup, while watching the deploy.
- Pull request 2 changes what the stack manages; the `.env` step above is required before it merges.
- The three-day wait means routine updates arrive three days later than today.

## Out of scope

- Autoheal's image is built on Alpine 3.18, which no longer gets updates. Both the old and the current digest are
  affected. Replacing autoheal is a separate decision.
- Triage of the open Trivy alerts: the monthly review continues.
- Server-side changes other than the `.env` line.
