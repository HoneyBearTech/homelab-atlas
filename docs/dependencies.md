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
| Helper image for backups (busybox) | [`scripts/lib.sh`](../scripts/lib.sh) (sourced by `backup.sh` and `restore.sh`) | version tag and digest | Docker |
| Linters and scanners used only by CI (actionlint, gitleaks, Trivy) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), [`scan.yml`](../.github/workflows/scan.yml), [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) (the actionlint image) | version tag and digest | Docker |
| GitLab mirror job images (alpine/git, docker, python, gitleaks, actionlint) | [`.gitlab-ci.yml`](../.gitlab-ci.yml) | version tag and digest | GitLab CI |
| Pre-commit hooks | [`.pre-commit-config.yaml`](../.pre-commit-config.yaml) | full commit SHA of the release (version in a `# frozen:` comment); `shellcheck-py` by exact version | pre-commit |
| GitHub Actions | [`.github/workflows/`](../.github/workflows/) | full commit SHA (version in a comment) | GitHub Actions |

Each release carries a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)). To update the pinned Python tools, edit
`requirements-dev.in` if needed and run `pip-compile --generate-hashes --strip-extras requirements-dev.in`.

## Tracking dependencies

- **Renovate** ([`.github/renovate.json5`](../.github/renovate.json5)) checks weekly (Mondays, 06:00 to 10:00 UTC)
  for new image versions in the Compose file, new tool versions, new Action versions, new pre-commit hook versions
  and new digests of the images that workflow steps, the pre-commit config and the backup scripts run, and opens a
  pull request for each. It reads `compose.yaml`, `requirements-dev.txt`, the workflows, `.gitlab-ci.yml`,
  `.pre-commit-config.yaml` and `scripts/*.sh`, and nothing else. Its commits are made through
  GitHub's API, so they're signed, and carry a DCO sign-off. Dependabot alerts stay on; Dependabot no longer opens
  version updates.
- **Patch, minor and major updates merge automatically**: Renovate turns on GitHub's auto-merge for each of its
  pull requests, so they're squash-merged once every required check has passed (CI with the Compose policy check,
  CodeQL, dependency review, DCO). Nothing skips a check, and a failing update stays open for the maintainer.
- **Image rebuilds are proposed, and merge, like any other update**: a new digest under the same tag (a rebuild of
  the same app version, with newer base packages), busybox included, except that they
  skip the three-day wait (below).
- **A new version waits three days after its release** (`minimumReleaseAge`), so a release that is pulled or
  fixed within days doesn't reach the server; the pull request then merges as above. Fixes for vulnerability alerts
  skip the wait. An image rebuild (a new digest under the same tag) skips it too: Docker Hub dates a rebuild by
  the tag's last push, so a tag rebuilt about weekly would never get through the Monday-only schedule, and rebuilds
  are mostly base-image security refreshes, still gated by the smoke test and the required checks. A moved tag on a
  pre-commit hook or an Action keeps the wait. A version update
  from a registry that reports no release date isn't held back either.
- **Each tool's two pins usually move in one pull request**: ruff, yamllint and shellcheck-py are pinned in
  `requirements-dev.txt` and in `.pre-commit-config.yaml`, and Renovate groups them. Grouping is best-effort: a
  member that hasn't waited out its three days is left out of an otherwise ready group, so the two pins can differ
  for a week. That's harmless: CI uses `requirements-dev.txt`.
- **The smoke test's runner label is left alone**: `runs-on: ubuntu-24.04` in `ci.yml` matches the server's Ubuntu
  release, so Renovate doesn't update runner labels (a rule on `github-runners` in its configuration). It moves with
  the server, by hand.
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
- The CI-only images in `run:` steps, the pre-commit config's actionlint image and the backup scripts' busybox
  image are pinned the same way and Renovate
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

### Current findings

Triaged on **15 November 2026** from the weekly scan of `main` ([`scan.yml`](../.github/workflows/scan.yml):
Trivy 0.76.2, HIGH and CRITICAL findings that have a fix, Linux amd64 images). Code scanning has **468 open
alerts** from it: 22 critical, 444 high and 2 medium (code scanning's severity, from each advisory's score; Trivy
calls the two medium ones HIGH). They come from 86 advisories, grouped below by package and answer. Every pinned
image was scanned again with the same Trivy version and flags, and the counts match code scanning exactly. Radarr,
Sonarr and Bazarr share one image with their 4K service, so each of their alerts is counted once. Reachability was
judged from each image's contents and the app's source at the pinned version.

- **20 are fixed by an update** that already exists (rows 1 and 2), and the updates merge after the smoke test like
  any other. Renovate proposes the Sonarr rebuild on its next run (Monday, 16 November 2026). Dozzle v11.4.3 was
  released on 13 November, so its three-day wait ends after that run: Renovate proposes it on Monday,
  23 November (on the 16th it may offer v11.4.2, which doesn't fix row 2).
- **114 are dismissed as not reachable** in this stack, as "won't fix" in code scanning, each with its row's
  reason and a link to this section. A dismissed alert can be reopened: the row says what would make it reachable.
- **334 stay open.** They are plausibly reachable and no stable release fixes them yet; they close as the apps ship
  fixes. The mitigation for them is below.

| # | Image | Package | Alerts | Outcome | Why |
| ---: | --- | --- | ---: | --- | --- |
| 1 | Sonarr | `krb5-libs`, `libxslt` | 19 | Fixed by update | A rebuild of `version-4.0.20.3014` ships krb5-libs 1.22.3-r0 and libxslt 1.1.43-r4 (the pinned build has 1.22.2-r1 and 1.1.43-r3). Scanned: 56 alerts to 37, none new. |
| 2 | Dozzle | `golang.org/x/net` | 1 | Fixed by update | Dozzle v11.4.3 (scanned: no findings); Renovate proposes it on 23 November. The Dozzle hub on the other host must move to v11.4.3 too: the agent stays on the hub's version (`compose.yaml`). |
| 3 | Radarr | `krb5-libs` | 16 | Dismissed: not reachable | The flaws are in the Kerberos KDC, kadmind, NegoEx and RPCSEC_GSS. The package also ships the KDC's and kadmind's libraries, but the image has no `krb5kdc` or `kadmind` binary to load them, no `/etc/gss` (so no NegoEx mechanism), and Radarr never accepts GSSAPI logins. Radarr's newest build (8 November) has the older packages, which Lidarr's pinned build and the Sonarr rebuild in row 1 have already replaced; a Radarr rebuild would fix it. |
| 4 | Radarr | `libxslt` | 3 | Dismissed: not reachable | xmlstarlet, `xsltproc` and libexslt link it, but the image runs only xmlstarlet, to read Radarr's own `config.xml`. Nothing processes untrusted XML or XSLT. Fixed by the same Radarr rebuild. |
| 5 | Radarr, Lidarr | .NET 8.0.27 runtime and ASP.NET Core | 292 (146 each) | Open | 22 advisories, 2 of them critical request smuggling in the web server (CVE-2026-88092, CVE-2026-70188), which acts before any login. The apps' HTTP client fetches from indexers and metadata servers with Brotli decompression and HTTP/2 on, so the Brotli out-of-bounds write (GHSA-p3jp-9v83-76w9) and the HTTP/2 flood (CVE-2026-50651) are reachable from any server the app fetches from. Fixed in .NET 8.0.29 to 8.0.34; no stable Radarr or Lidarr release ships them. **The most urgent open group** (below). |
| 6 | Sonarr | .NET 6.0.13 runtime and ASP.NET Core, `System.Text.Json` | 7 | Open | Kept open without a per-advisory check: two are in ASP.NET Core Identity (CVE-2023-33170, CVE-2025-24070), which Sonarr doesn't use. The real issue is the runtime: .NET 6 has been out of support since November 2024, and these 7 are only what Trivy reports. The Sonarr rebuild in row 1 keeps them. |
| 7 | Radarr, Lidarr, Sonarr | `SixLabors.ImageSharp` 3.1.12: CVE-2026-106113 in all three; CVE-2026-106110 and -106115 in Radarr and Sonarr | 42 (18, 6, 18) | Dismissed: not reachable | The flaws are in HistogramEqualization, which none of the apps runs, and in the TIFF fax encoders. Radarr and Sonarr only load, resize and save posters as JPEG (or PNG, for logos), never TIFF. |
| 8 | Radarr, Lidarr, Sonarr | `SixLabors.ImageSharp` 3.1.12: CVE-2026-106118 in all three; CVE-2026-106110 and -106115 in Lidarr | 30 (6, 18, 6) | Open | CVE-2026-106118 is a heap out-of-bounds write in the tiled fax TIFF decoder. The apps load images with ImageSharp's default configuration, which decodes whatever a metadata or cover-art server returns, TIFF included. Lidarr also keeps the image URL's extension for the resized file, and ImageSharp picks the encoder from it, so a `.tif` cover is decoded and re-encoded as TIFF: that reaches the fax encoder flaws (CVE-2026-106110, -106115). No setting turns either off. |
| 9 | Radarr, Lidarr, Sonarr | `System.Security.Cryptography.Pkcs` 8.0.1 | 16 (5, 5, 6) | Dismissed: not reachable | The flaw is in `SignedCms.CheckSignature`, which none of the apps calls: they only send email and never verify S/MIME signatures. |
| 10 | Bazarr, SABnzbd | `certifi` 2026.6.17 | 2 (critical) | Open | The bundle trusts emSign roots whose intermediate keys were compromised. Bazarr's HTTP client trusts it, and SABnzbd points `SSL_CERT_FILE` at it for all of its TLS (Usenet servers and indexers). An attack needs someone on the network path holding one of those keys. Bazarr's development line (v1.6.3-beta) has the fix; no stable release yet. |
| 11 | Bazarr, SABnzbd | `oauthlib` 3.3.1 | 4 | Dismissed: not reachable | Both flaws are in OAuth 2 server-side token and device-code endpoints. Both apps use oauthlib only as a client, through Apprise's Twitter notifier. |
| 12 | Bazarr | `dnspython` | 2 | Dismissed: not reachable | Bazarr uses dnspython only when the `dns_resolvers` environment variable is set, which this stack never sets, and never parses zone files. Setting `dns_resolvers` makes it reachable: reopen them then. |
| 13 | Bazarr | `msgpack` | 1 | Dismissed: not reachable | Bazarr's SignalR client and Socket.IO server use JSON; nothing deserializes MessagePack from untrusted input. |
| 14 | Bazarr | `soupsieve` (CVE-2026-126191) | 1 | Dismissed: not reachable | The flaw needs an attacker-supplied CSS selector; Bazarr's subtitle providers use only fixed selectors in its code. |
| 15 | Bazarr | `soupsieve` (CVE-2026-126190) | 1 | Open | Denial of service only: selectors with descendant combinators run on HTML from subtitle sites. |
| 16 | Bazarr | `urllib3` (CVE-2026-97687) | 1 | Dismissed: not reachable | It needs an HTTPS proxy. Bazarr's settings allow only HTTP and SOCKS proxies, and this stack sets no `HTTPS_PROXY`. An `https://` value in `HTTPS_PROXY` would make it reachable: reopen it then. |
| 17 | Bazarr, SABnzbd | `urllib3` (CVE-2026-97689) | 2 | Open | Memory exhaustion from a chunked response: in Bazarr from a subtitle-provider server, in SABnzbd from any notification service Apprise sends to, a redirect it returns, or anyone on the network path to an `http://` one. `compose.yaml` sets no memory limits, so nothing in the stack contains it. |
| 18 | SABnzbd | `urllib3` (CVE-2026-97687) | 1 | Dismissed: not reachable | It needs an HTTPS proxy for the requests library inside Apprise, SABnzbd's only use of urllib3, and this stack sets none. An `https://` value in `HTTPS_PROXY` would make it reachable. |
| 19 | SABnzbd | `PyJWT` | 1 | Dismissed: not reachable | The flaw is in `PyJWK` and `from_jwk`, which nothing in SABnzbd uses. Only oauthlib imports `jwt`, on demand, for RSA signing (OAuth 1) and RS256 tokens (OAuth 2), and never through `PyJWK`; Apprise's Twitter notifier, SABnzbd's only use of oauthlib, signs with HMAC-SHA1. |
| 20 | Seerr | `nodemailer` 7.0.13 and 9.1.1 | 6 | Dismissed: not reachable | Seerr sends mail with its own nodemailer 10.2.1. The 7.0.13 copy (from email-templates) and the 9.1.1 copy (from preview-email) are never used: Seerr passes its own transport and turns previews off. This covers CVE-2026-90776, whose reachability the 13 November snapshot left open. |
| 21 | Seerr | `brace-expansion`, `ip-address`, `pacote` (2), `picomatch`, `sigstore` | 10 | Dismissed: not reachable | Part of the npm CLI in the Node.js base image. npm only starts Seerr (`npm start`), and on each start its update check fetches the registry's manifest for `npm@latest`. That fixed lookup never resolves git specs (pacote), verifies signatures (sigstore), expands outside globs (picomatch, brace-expansion) or goes through a SOCKS proxy (ip-address); npm never installs anything. |
| 22 | Recyclarr | `git`, `git-init-template` | 6 | Dismissed: not reachable | Recyclarr runs only `git init`, `fetch`, `status` and `reset --hard` on its guide repositories; it never merges, clones submodules or uses fast-import. |
| 23 | Recyclarr | `libexpat` | 4 | Dismissed: not reachable | Only git links it, for WebDAV push (`http-push`), which Recyclarr never uses. |
| | | **Total** | **468** | | 20 fixed by update, 114 dismissed, 334 open. |

**Mitigation for the open findings** (rows 5, 6, 8, 10, 15 and 17). These limit who and what can reach the apps;
they don't remove the bugs.

- **Keep the apps' ports reachable from the LAN only.** The stack doesn't enforce this: `compose.yaml` publishes
  every port on all of the host's addresses, IPv4 and IPv6, and Docker-published ports bypass host firewalls such
  as `ufw` ([installing.md](installing.md#running-it-securely)). It's the operator's job, at the router or a
  firewall in front of the host. Row 5's request-smuggling flaws act in the web server before any login, so only
  this and a reverse proxy that rejects ambiguous requests (below) mitigate them.
- **Turn on each app's Forms login** ([installing.md](installing.md#running-it-securely)). It protects the apps'
  pages and API, not the web server underneath.
- **Enable only trusted indexers and subtitle providers**, and send SABnzbd's notifications only to `https://`
  services: rows 15 and 17 are triggered by what those servers send back.
- **Any reverse proxy put in front of an app must reject ambiguous requests** (for example, both `Content-Length`
  and `Transfer-Encoding`), so the request-smuggling flaws in row 5 can't pass through it.
- **No configuration mitigation** exists for row 8 (ImageSharp's TIFF decoder, and Lidarr's TIFF encoders) or for
  row 5's Brotli out-of-bounds write (GHSA-p3jp-9v83-76w9). The Brotli flaw is memory corruption triggered by a
  response from the metadata servers the apps use, which the operator doesn't choose, which makes row 5 the most
  urgent open group. It goes when Radarr and Lidarr ship a newer runtime.

**Runtimes out of support.** Radarr and Lidarr bundle .NET 8.0.27; .NET 8 went out of support on 10 November 2026,
and 8.0.34 was its last patch. Sonarr bundles .NET 6.0.13, out of support since 12 November 2024; Trivy reports
only 7 of its advisories, so that count understates the exposure. Only the prerelease lines move to .NET 10:
Radarr 7 and Sonarr 5. Lidarr has no release that does (its development build, 3.2.1, is still on .NET 8.0.27).
Running prereleases here is out of scope; the [roadmap](roadmap.md#security-and-project-health) tracks the move to
the stable .NET 10 releases.

**ImageSharp.** Upstream's fix (8 October 2026, in Radarr, Sonarr and Lidarr) restricts ImageSharp's decoders and
encoders to JPEG, PNG and WebP. It is only in the prerelease lines, and it keeps ImageSharp 3.1.12 and suppresses
the advisories, so the scan will keep reporting row 8 after a stable release ships it. Row 8 is dismissed once that
release is pinned.

**The October PyJWT dismissals.** The six SABnzbd PyJWT alerts dismissed on 7 October 2026 say that no library in
the image imports `jwt`. oauthlib does, on demand, for RSA signing (OAuth 1) and RS256 tokens (OAuth 2); SABnzbd's
only use of oauthlib, Apprise's Twitter notifier, signs with HMAC-SHA1 and never reaches either. So they stay
dismissed, and their comments are corrected to say so when this triage's dismissals are made. Row 19 uses the same
reasoning.

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

The tested newer `willfarrell/autoheal` digest still used **Alpine 3.18.12, which is EOL**, so it was rejected, and
Renovate's later pin (`d674ad9`) was on the same base. Its zero findings were unreliable evidence of security. That
image has since been replaced by `ghcr.io/tmknight/docker-autoheal:0.14.1` (Alpine 3.24, pinned by tag and digest,
no policy exception; [security.md](security.md#why-this-autoheal)); the table and inventory above describe the
earlier image and were not re-scanned. Dozzle v11.4.2 showed no measured remediation
benefit, so its previous pin remains. Recyclarr and socket-proxy had no distinct candidate.

#### Coverage limits

- These scans cover Linux amd64 only, not every architecture in a multi-architecture image index.
- Dozzle has application-package coverage only; full OS/runtime coverage is absent.
- Bazarr and SABnzbd report third-party-SBOM
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
socket-proxy were added after that scan; autoheal's then image (`willfarrell/autoheal`) had `latest` as its only maintained tag, so it was pinned as `latest@sha256:…` with a policy exception; it is now `ghcr.io/tmknight/docker-autoheal` at a versioned tag and digest, which Renovate bumps like the other images.

## Licenses

homelab-atlas's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses: `tmknight/docker-autoheal` is GPL-3.0, and the
stack runs the published image unmodified (it doesn't copy or change its code), so the licence puts nothing on this
repository's own files.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff finding fails CI; a
deliberate exception is a per-line `noqa` with the reason next to it.
