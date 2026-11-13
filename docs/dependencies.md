# Dependencies and vulnerability management

How homelab-atlas chooses, obtains, tracks and updates what it's built from, and what happens when one of
those dependencies has a vulnerability.

homelab-atlas's dependencies are almost entirely the **container images** it runs. The rest are the tools
its checks and tests use and the GitHub Actions in its workflows. Its own code, the policy checker, uses
only the Python standard library.

## Choosing a dependency

A new image or tool must:

- be open source under an OSI-approved license (the apps themselves are typically GPL-3.0, which is fine:
  homelab-atlas pins and runs them, it doesn't redistribute or link them);
- be actively maintained: releases in the last year, security issues answered, and published for the
  host's architecture;
- come from the project itself or a widely used, reproducible packager (linuxserver.io), from its official
  registry; and
- be worth it: a new service needs a reason in the pull request that adds it.

## Obtaining dependencies

| Dependency | Declared in | Pinned by | Fetched by |
| --- | --- | --- | --- |
| The stack's images | `compose.yaml` | version tag and digest | `docker compose pull` |
| Check and test tools (pytest, coverage, ruff, yamllint, shellcheck) | [`requirements-dev.in`](../requirements-dev.in) → [`requirements-dev.txt`](../requirements-dev.txt) | exact version and SHA-256 hashes (`pip-compile --generate-hashes`) | `pip install --require-hashes --no-deps` |
| Helper image for backups (busybox) | [`scripts/backup.sh`](../scripts/backup.sh), [`scripts/restore.sh`](../scripts/restore.sh) | version tag and digest | Docker |
| Linters and scanners used only by CI (actionlint, gitleaks, Trivy) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), [`scan.yml`](../.github/workflows/scan.yml) | version tag and digest | Docker |
| GitHub Actions | [`.github/workflows/`](../.github/workflows/) | full commit SHA (version in a comment) | GitHub Actions |

Each release carries a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)). To update the pinned Python tools, edit
`requirements-dev.in` if needed and run `pip-compile --generate-hashes --strip-extras requirements-dev.in`.

## Tracking dependencies

- **Renovate** ([`.github/renovate.json5`](../.github/renovate.json5)) checks weekly (Mondays, 06:00 to 10:00 UTC)
  for new image versions in the Compose file, new tool versions, new Action versions and new digests of the images
  that workflow steps and the backup scripts run, and opens a pull request for each. Its commits are made through
  GitHub's API, so they're signed, and carry a DCO sign-off. Dependabot alerts stay on; Dependabot no longer opens
  version updates.
- **Patch, minor and major updates merge automatically**: Renovate turns on GitHub's auto-merge for each of its
  pull requests, so they're squash-merged once every required check has passed (CI with the Compose policy check,
  CodeQL, dependency review, DCO). Nothing skips a check, and a failing update stays open for the maintainer.
- **Image rebuilds merge automatically too**: a pull request that only moves an image to a new digest under the
  same tag (a rebuild of the same app version, with newer base packages) and changes nothing else in
  `compose.yaml`.
- **linuxserver.io images are pinned by their `version-<app version>` tag** (`radarr:version-6.4.4.10685@sha256:…`),
  which always points at the newest build of that app version; Renovate reads it with a version scheme of its own
  (`packageRules` in its configuration) and never proposes the build tags (`6.4.4.10685-ls320`). With the
  `version-` tag it proposes both new app versions and rebuilds (a new digest under the same tag). socket-proxy uses its bare version tag (`3.4.6`) for the same reason.
- **Major updates merge automatically too** (the maintainer's decision, 2026-10-14), and so reach the server
  unattended. A new major version can migrate its database one way: the nightly
  [scheduled backup](installing.md#scheduled-backups) and a revert pull request are the way back, and a revert alone
  doesn't undo the migration, so the service's data is restored from the backup
  ([upgrading.md](upgrading.md#rolling-back)).
- **A merge deploys.** The maintainer's server follows `main` with a pull agent, so every merge, the automatic
  ones included, reaches it within about two minutes ([upgrading.md](upgrading.md#following-main)).
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- The CI-only images in `run:` steps and the backup scripts' busybox image are pinned the same way and Renovate
  proposes their new digests and versions too (a custom manager in its configuration); they merge automatically
  like the rest.
- **Nothing on the host updates from a registry.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed. The pull agent only applies commits merged into `main`.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the apps' and images' own advisories, and a weekly
scan of the pinned digests ([`scan.yml`](../.github/workflows/scan.yml): Trivy, HIGH and CRITICAL findings that
have a fix, reported to code scanning with one category per image). Each finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Renovate pull request usually already does) and release.
   A fix for an exploitable critical or high-severity vulnerability goes out in a patch release within 30
   days; others go out with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (which ports are
   published, what the app does with untrusted input). If it is, mitigate it where possible (for example,
   stop publishing a port) and say so in the release notes; otherwise record the reason when dismissing
   the alert. Either way, it's fixed by a bump when upstream ships one.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

### Historical vulnerability snapshot

The removed findings summarized a scan triaged on 22 October 2026 against the image versions pinned at that time. That snapshot is no longer current: Compose now pins newer versions and digests, including Seerr `v3.5.1`, Lidarr `3.1.6.5079`, and Recyclarr `8.8.1`. It recorded 505 open alerts (32 critical, 460 high and 13 medium) across the then-pinned images. The old counts and component assessments do not describe the current digests and must not guide current update or exposure decisions.

The historical scan used the weekly Trivy workflow plus a same-day scan of the same digests and newer builds, with then-current vulnerability database data. Its exact scan artifacts and digest list are not reproduced here, so findings are retained only as historical context and are not asserted for the current Compose inventory. Current findings should be taken from the weekly image scan for the exact digests in [`compose.yaml`](../compose.yaml) and triaged against those results. A newer tag alone does not establish that an image is vulnerability-free.

**Earlier triage (7 October 2026),** after the first scan (527 alerts). FlareSolverr (348 alerts, most of them in
its Chromium, the only findings reachable from the internet) was removed: no indexer was configured to use it, and
its newest release still shipped an old Chromium. The unmaintained webnut image (last published in 2015) went the
same day. Bazarr `v1.6.2-ls367` and Recyclarr `8.7.3` fixed 17. Seven alerts were dismissed as not reachable, each
with its reason in code scanning: Bazarr's `setuptools` (`PackageIndex` path traversal; Bazarr never uses
`PackageIndex` or installs packages) and SABnzbd's `PyJWT` (six; installed as a requirement, but nothing in
SABnzbd imports it; only oauthlib does, in code paths SABnzbd's notifications don't use). autoheal and
socket-proxy were added after that scan; autoheal's only maintained tag is `latest` (its versioned tags stop at
1.2.0 from 2021), so it's pinned as `latest@sha256:…` with a policy exception, and bumped by hand with the other
hand-pinned images if Renovate doesn't propose new digests for it.

## Licenses

homelab-atlas's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff finding fails CI; a
deliberate exception is a per-line `noqa` with the reason next to it.
