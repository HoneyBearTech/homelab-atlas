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

### Current-image scan snapshot — 13 November 2026 UTC

This static image-content snapshot compares source `main` at `bc8f6d1` with the six image updates below;
it does not describe deployed state. Trivy 0.75.0 scanned Linux amd64 images directly from registries,
with identical policy and frozen databases for all baseline and candidate scans. Ten unique image
references cover 13 services: Radarr, Sonarr and Bazarr each share an image with their 4K service and
are counted once. The full snapshot applies no severity or unfixed-finding filter.

The vulnerability database's `UpdatedAt` was `2026-11-12T18:57:38.498853214Z`. Full database SHA-256 hashes:

- Vulnerability DB: `024e3e42822e93b63a119eae8997d24425a8703b7bb463e5afc1bcec92da2e67`
- Java DB: `c7667e7d7d335b7a801b4ed11c1a886d0928eec65bf7e5b973762e8715cf4263`

Raw reports and registry/config identities are retained as local evidence in ignored `.agent/` artifacts.
All 18 baseline/candidate reports passed identity and platform checks, and full database hashes stayed
unchanged throughout scanning. Exact post-update inventory (tags may move; these digests fix the snapshot):

- **radarr**: `lscr.io/linuxserver/radarr:version-6.4.4.10685@sha256:51a9ac2a9eb47afc833541e5fd6c11b86eb9f810694c22fa2429e3078e9194b2`
- **lidarr**: `lscr.io/linuxserver/lidarr:version-3.1.6.5079@sha256:a91ef0642c15c9bd7c4260fee98fa99972c61601e37c8a96411d6a9cf0e9ad40`
- **seerr**: `ghcr.io/seerr-team/seerr:v3.5.2@sha256:aadee014b40e28cf9aa4928bc9d1183a6eb08f8c44d543cddc9efdcb16549be2`
- **autoheal**: `willfarrell/autoheal:latest@sha256:e7f42d5365c7c4490dd0cafc2858bb9fd2d64a274448d2de2bb5c386f1af7a0f`
- **sonarr**: `lscr.io/linuxserver/sonarr:version-4.0.20.3014@sha256:673dc4609a5672bc8e46069c86ffcea283a86b48d34a6c93d8da8c24a1b87571`
- **bazarr**: `lscr.io/linuxserver/bazarr:version-v1.6.2@sha256:832820dec70bce9e912c6eee7a95baf6551e03dbc63325a7208daaa455423752`
- **sabnzbd**: `lscr.io/linuxserver/sabnzbd:version-5.1.3@sha256:b356d0a9b22db584e9005364ec4e752dfc081ce501b7145e9a5c0bb38e4d1ba4`
- **recyclarr**: `recyclarr/recyclarr:8.8.1@sha256:3e9c41b9ec29bbf65fe846864058730d321a21f7695d8c0d9437b73e34d50ad9`
- **dozzle**: `amir20/dozzle:v11.4.1@sha256:915a5acf91b01bb4d11de1fde7e30d55646211240269e4404c03a6f71c5fc91e`
- **socket-proxy**: `lscr.io/linuxserver/socket-proxy:3.4.7@sha256:823dda971e9a3951257eb251586a804199819fe1587c35faa43adc7b52a2ff16`

| Image | Baseline full occurrences | Updated full occurrences | Baseline fix-available HIGH/CRITICAL | Updated fix-available HIGH/CRITICAL |
| --- | ---: | ---: | ---: | ---: |
| Radarr | 273 | 272 | 194 | 194 |
| Lidarr | 273 | 247 | 194 | 175 |
| Seerr | 353 | 60 | 151 | 16 |
| Autoheal | 0 | 0 | 0 | 0 |
| Sonarr | 145 | 94 | 61 | 56 |
| Bazarr | 40 | 18 | 23 | 8 |
| SABnzbd | 27 | 26 | 13 | 13 |
| Recyclarr | 18 | 18 | 10 | 10 |
| Dozzle | 4 | 4 | 1 | 1 |
| Socket proxy | 1 | 1 | 0 | 0 |

Full package/advisory occurrences fall from **1,134 to 740**, distinct advisory IDs across images from
**388 to 164**, and unique `(image, advisory ID)` pairs from **508 to 250**. Fix-available HIGH/CRITICAL
occurrences fall from **647 to 473**. Updated severities are **23 CRITICAL, 451 HIGH, 260 MEDIUM, 4 LOW,
and 2 UNKNOWN**: all HIGH/CRITICAL occurrences total 474, one more than the fix-available subset.
These are package/advisory occurrences in image contents, not exploitable application counts or unique
CVE counts. A removed scanner match is not proof of remediation or absence of a vulnerability.

#### Selection and remaining findings

Radarr, Lidarr, Sonarr, Bazarr and SABnzbd use publisher rebuilds of their existing application versions.
Their reported contract metadata is unchanged, and no newly detected advisory IDs occurred in these
five comparisons. Radarr and SABnzbd each remove one MEDIUM occurrence despite unchanged HIGH/CRITICAL
counts; the other rebuilds reduce those counts as shown above.

Seerr moves to [v3.5.2](https://github.com/seerr-team/seerr/releases/tag/v3.5.2), whose release notes
recommend prompt upgrading for three security fixes, with advisories planned for 15 November 2026.
Its fix-available HIGH/CRITICAL occurrences fall from 151 to 16 and its CRITICAL occurrences from 11
to zero. This does not establish a correspondence between those upstream fixes and particular scan IDs.
Two newly detected Nodemailer 9.1.1 findings remain unsuppressed:

- Trivy ID **CVE-2026-90776**, HIGH, reports a fix in 10.0.5. The
  [upstream HIGH advisory](https://github.com/nodemailer/nodemailer/security/advisories/GHSA-prgh-xp8r-p3m5)
  describes resource exhaustion from attacker-controlled address parsing in 9.1.0–10.0.4. The upstream
  page does not currently assign a CVE; this document does not assert an independently verified alias.
  Seerr-specific reachability has not been assessed.
- [GHSA-g57g-f23g-4646](https://github.com/nodemailer/nodemailer/security/advisories/GHSA-g57g-f23g-4646),
  MEDIUM, reports a fix in 10.0.9 and concerns malformed recipient handling. The scan does not demonstrate
  unauthorized mail delivery by Seerr.

Seerr's release also includes a SQLite migration-related change. Reopening migrated data with v3.5.1
has not been validated. **A merge deploys**, as described above: operators need a consistent pre-upgrade
Seerr config/SQLite backup before the later upgrade; an optional external PostgreSQL database needs a
separate database backup. Follow [upgrade and rollback guidance](upgrading.md#rolling-back).
An operational rollback may require both the previous image and pre-upgrade data and can lose changes
made after that backup. This repository change does not perform or verify live backups, restores or
migrations, and reverting an image pin alone does not establish migration reversibility.

The tested newer autoheal digest still uses **Alpine 3.18.12, which is EOL**, so it was rejected and the
existing pin remains. Its zero findings are unreliable evidence of security. Replacement or a supported
rebuild remains unresolved; no alternative was validated. Dozzle v11.4.2 showed no measured remediation
benefit, so its previous pin remains. Recyclarr and socket-proxy had no distinct candidate.

#### Coverage limits

- These scans cover Linux amd64 only, not every architecture in a multi-architecture image index.
- Dozzle has application-package coverage only; full OS/runtime coverage is absent.
- Autoheal's EOL base weakens vulnerability detection. Bazarr and SABnzbd report third-party-SBOM
  accuracy warnings.
- Per the [official Alpine release table](https://alpinelinux.org/releases/), Seerr and Bazarr's Alpine
  3.23 has main-only support, not assured support for all community packages. The Radarr, Lidarr,
  Sonarr and SABnzbd candidate base Alpine 3.24 has main/community support in the recorded evidence.
- Contract metadata comparison does not prove read-only/non-root/custom-PUID behavior, health checks,
  runtime exploitability or migration reversibility. No runtime or deployment test was performed.
- Package-level reported fixes do not establish which publisher image resolves each finding. Residual
  findings remain unsuppressed and require upstream updates or further reachability triage.

### Historical vulnerability snapshot

The removed findings summarized a scan triaged on 22 October 2026 against the image versions pinned at that time. That snapshot is no longer current: Compose now pins newer versions and digests, including Seerr `v3.5.2`, Lidarr `3.1.6.5079`, and Recyclarr `8.8.1`. It recorded 505 open alerts (32 critical, 460 high and 13 medium) across the then-pinned images. The old counts and component assessments do not describe the current digests and must not guide current update or exposure decisions.

The historical scan used the weekly Trivy workflow plus a same-day scan of the same digests and newer builds, with then-current vulnerability database data. Its exact scan artifacts and digest list are not reproduced here, so findings are retained only as historical context and are not asserted for the current Compose inventory. For ongoing findings beyond the dated snapshot above, use the weekly image scan for the exact digests in [`compose.yaml`](../compose.yaml) and triaged against those results. A newer tag alone does not establish that an image is vulnerability-free.

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
