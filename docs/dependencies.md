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

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly for new image
  versions in the Compose file, new tool versions and new Action versions, and opens a pull request for
  each. Dependabot alerts and security updates are on.
- **Patch and minor updates merge automatically**
  ([`.github/workflows/dependabot-auto-merge.yml`](../.github/workflows/dependabot-auto-merge.yml)): for the
  images, the Python tools and the GitHub Actions, they're squash-merged once every required check has passed
  (CI with the Compose policy check, CodeQL, dependency review). Nothing skips a check, and a failing update
  stays open for the maintainer.
- **Major updates are merged by hand**, after reading the app's release notes: a new major version can migrate
  its database one way. So is any update Dependabot can't classify as patch, minor or major.
- **A merge doesn't deploy.** The server runs what it last pulled; updates reach it when the operator pulls
  and redeploys, with a backup first ([upgrading.md](upgrading.md)).
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- The CI-only images in `run:` steps and the backup scripts' busybox image aren't seen by Dependabot; they're
  bumped by hand at least every quarter.
- **Nothing updates itself on the host.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the apps' and images' own advisories, and a weekly
scan of the pinned digests ([`scan.yml`](../.github/workflows/scan.yml): Trivy, HIGH and CRITICAL findings that
have a fix, reported to code scanning with one category per image). Each finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Dependabot pull request usually already does) and release.
   A fix for an exploitable critical or high-severity vulnerability goes out in a patch release within 30
   days; others go out with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (which ports are
   published, what the app does with untrusted input). If it is, mitigate it where possible (for example,
   stop publishing a port) and say so in the release notes; otherwise record the reason when dismissing
   the alert. Either way, it's fixed by a bump when upstream ships one.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

### Current findings

Triaged 7 October 2026, after the first image scan (527 alerts, every one HIGH or CRITICAL with a fixed package
version somewhere upstream). Every image is maintained.

**Added after the scan.** autoheal (`willfarrell/autoheal`) and socket-proxy (`linuxserver/socket-proxy`).
autoheal's only maintained tag is `latest` (its versioned tags stop at 1.2.0 from 2021), so it is pinned as
`latest@sha256:…` with a policy exception; if Dependabot doesn't propose new digests for it, it's bumped by hand
with the other hand-pinned images.

**Removed from the stack.** FlareSolverr (348 alerts, most of them in its Chromium, the only findings reachable
from the internet): no indexer was configured to use it, and its newest release still shipped an old Chromium.
The unmaintained webnut image (last published in 2015) was removed the same day.

**Fixed by a bump.** Bazarr `v1.6.2-ls367` (13 alerts: Alpine's Python 3.12 and PCRE2) and Recyclarr `8.7.3`
(all 4: OpenSSL, Expat, PCRE2).

**Dismissed as not reachable** (7 alerts, each with this reason in code scanning):

| Image | Package | Why it can't be reached |
| --- | --- | --- |
| Bazarr | `setuptools` (`PackageIndex` path traversal) | Bazarr never uses `PackageIndex` or installs packages |
| SABnzbd | `PyJWT` (6) | Installed as a requirement, but neither SABnzbd nor any library in the image imports it |

**Open, waiting for upstream** (155). No newer image exists yet with the fixed package; each alert closes by
itself when Dependabot's bump to such an image is merged and the scan runs again.

- **The .NET runtimes bundled into Radarr (8.0.27, 48), Lidarr (8.0.12, 81, 5 critical in ASP.NET Core) and
  Sonarr (6.0.13, 7).** Reachable through each app's web UI and API. Fixed when the Servarr projects ship a build
  on a newer runtime; Sonarr v4 is on .NET 6, which is out of support, so Sonarr's fixes come with v5.
  Mitigated by keeping the UIs on the LAN with authentication on ([installing.md](installing.md#running-it-securely)).
- **Python and urllib3 in SABnzbd and Bazarr** (`python3` 3.14.7 in SABnzbd; urllib3 2.7.0 and msgpack in
  both or either). Fixed in the next linuxserver.io build that picks up the new packages.

## Licenses

homelab-atlas's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff finding fails CI; a
deliberate exception is a per-line `noqa` with the reason next to it.
