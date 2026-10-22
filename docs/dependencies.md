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

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly (Mondays, 06:00 UTC) for
  new image versions in the Compose file, new tool versions and new Action versions, and opens a pull request for
  each. Dependabot alerts and security updates are on.
- **Patch, minor and major updates merge automatically**
  ([`.github/workflows/dependabot-auto-merge.yml`](../.github/workflows/dependabot-auto-merge.yml)): for the
  images, the Python tools and the GitHub Actions, they're squash-merged once every required check has passed
  (CI with the Compose policy check, CodeQL, dependency review). Nothing skips a check, and a failing update
  stays open for the maintainer.
- **Image rebuilds merge automatically too**: a pull request that only moves an image to a new digest under the
  same tag (a rebuild of the same app version, with newer base packages) and changes nothing else in
  `compose.yaml`.
- **linuxserver.io images are pinned by their `version-<app version>` tag** (`radarr:version-6.4.4.10685@sha256:…`),
  which always points at the newest build of that app version. Dependabot can't follow the build tags
  (`6.4.4.10685-ls320`): it reads `-ls320` as a suffix that must match exactly, so it never proposes another
  build. With the `version-` tag it proposes both new app versions and rebuilds (a new digest under the same
  tag). socket-proxy uses its bare version tag (`3.4.6`) for the same reason.
- **Major updates merge automatically too** (the maintainer's decision, 2026-10-14), and so reach the server
  unattended. A new major version can migrate its database one way: the nightly
  [scheduled backup](installing.md#scheduled-backups) and a revert pull request are the way back, and a revert alone
  doesn't undo the migration, so the service's data is restored from the backup
  ([upgrading.md](upgrading.md#rolling-back)). Any update Dependabot can't classify as patch, minor or major is
  still merged by hand.
- **A merge deploys.** The maintainer's server follows `main` with a pull agent, so every merge, the automatic
  ones included, reaches it within about two minutes ([upgrading.md](upgrading.md#following-main)).
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- The CI-only images in `run:` steps and the backup scripts' busybox image aren't seen by Dependabot; they're
  bumped by hand at least every quarter.
- **Nothing on the host updates from a registry.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed. The pull agent only applies commits merged into `main`.

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

Triaged 22 October 2026, from the weekly scan of `main` at `92fc0cb` (19 October), and from a scan that day of the
same digests and of the newer builds with the then-current vulnerability database. Where a verdict depends on what
an app actually uses, the pinned `linux/amd64` image was inspected (its files extracted, not run). The alerts stay
open in code scanning, so each closes by itself when an update ships the fix; none was dismissed.

**Totals: 505 open alerts**, 32 critical, 460 high and 13 medium in code scanning's rating (Trivy's own rating has
35 critical: it rates one `tar` vulnerability in Seerr higher). Counted once per image, they're 166 distinct
vulnerabilities: the scanner reports a vulnerability in a bundled .NET runtime once for every `*.deps.json` file
that lists the runtime, up to eight times per app. Apart from Seerr, whose v3.5.1 came out the day before, every
image was already on its newest stable release.

| Image | Alerts (critical) | Distinct | Mostly in |
| --- | --- | --- | --- |
| Lidarr `3.1.0.4875` | 180 (15) | 29 | its bundled .NET 8.0.12 runtime (24); ImageSharp 3.1.11 (3) |
| Radarr `6.4.4.10685` (both instances) | 146 (10) | 22 | its bundled .NET 8.0.27 runtime (18); ImageSharp 3.1.12 (3) |
| Seerr `v3.5.0` | 138 (7) | 96 | its Node.js packages: Next.js 16.2.6, handlebars, axios, sharp, npm's own |
| Sonarr `4.0.20.3014` (both instances) | 31 (0) | 11 | its bundled .NET 6.0.13 runtime and System.Text.Json (7); ImageSharp 3.1.12 (3) |
| Bazarr `v1.6.2` (both instances) | 6 (0) | 4 | urllib3 2.7.0, msgpack 1.1.2, Expat |
| SABnzbd `5.1.3` | 3 (0) | 3 | urllib3 2.7.0, Expat |
| Recyclarr `8.8.0` | 1 (0) | 1 | Expat |
| Dozzle, autoheal, socket-proxy | 0 | 0 | |

**Fixed by a bump** in pull request #50 (8 alerts, none critical; Dependabot hadn't proposed these yet):

- Seerr `v3.5.1`: Alpine's OpenSSL (CVE-2026-14456) and npm's own copy of `tar` (CVE-2026-59873, CVE-2026-59874,
  CVE-2026-73566). It also moves Node.js to 22.23.4, which stops trusting the compromised eMudhra intermediate
  certificates. It doesn't update Next.js, handlebars or the other packages below.
- Rebuilds under the same version tag: Lidarr `3.1.0.4875-ls45` (libX11, CVE-2026-88806), Bazarr `v1.6.2-ls369`
  and SABnzbd `5.1.3-ls278` (Expat, CVE-2026-77214). Bazarr's rebuild also brings Pillow 13.0.0, which fixes 19
  Pillow vulnerabilities (3 critical) that the next scan would have reported in the older build.

Radarr and Sonarr have newer builds too, but they change none of the findings; Dependabot proposes them as usual.

**Critical, waiting for upstream** (32 alerts; 10 vulnerabilities, 12 counted once per image):

| Image | Component | Vulnerability | Fixed in | Reachable here? | Action |
| --- | --- | --- | --- | --- | --- |
| Lidarr | ASP.NET Core 8.0.12 | CVE-2025-55315 (request smuggling) | .NET 8.0.21 | Yes, through Lidarr's web port. The advisory rates it for a signed-in attacker; its worst case needs a front end (a reverse proxy) that passes the malformed request on | Watch Lidarr (below) |
| Lidarr, Radarr | ASP.NET Core 8.0.12, 8.0.27 | CVE-2026-88092 (request smuggling) | .NET 8.0.32 | Yes, in principle, through each app's web port | Wait for a release on .NET 8.0.32 or later |
| Lidarr, Radarr | ASP.NET Core 8.0.12, 8.0.27 | CVE-2026-70188 (newline handling in HTTP/2) | .NET 8.0.32 | No: HTTP/2 only. The apps serve plain HTTP, where their web server (Kestrel) speaks only HTTP/1.1; it offers HTTP/2 only over the apps' own HTTPS, which is off by default. A reverse proxy talks HTTP/1.1 to them | Wait for upstream |
| Seerr | Next.js 16.2.6 (sharp's libheif) | GHSA-2xp9-vwfh-vxw4 (code execution in the image optimizer, AVIF) | Next.js 16.3.3 | **Yes, without signing in.** Seerr serves `/_next/image` to anyone who reaches its port, and the optimizer decodes images from four allow-listed hosts (TMDB, TheTVDB, Gravatar, plex.tv), some of which host user uploads | Watch Seerr (below) |
| Seerr | Next.js 16.2.6 | GHSA-vcvr-r3jv-pc5j (code execution in `next/og`) | Next.js 16.3.6 | No: Seerr's build doesn't use `next/og` or `ImageResponse` | Wait for upstream |
| Seerr | Next.js 16.2.6 | CVE-2026-75604 (code execution) | Next.js 16.3.3 | No: only on Windows-hosted servers; Seerr runs on Linux | Wait for upstream |
| Seerr | handlebars 4.7.8 | CVE-2026-33937, CVE-2026-106445, CVE-2026-106446 (code execution) | 4.7.9, 4.7.10 | No: installed only as an optional engine of the e-mail template library. Seerr's e-mail templates are Pug, nothing loads handlebars, and each flaw needs an attacker-supplied template or syntax tree | Wait for upstream |
| Seerr | proxy-addr 2.0.7 | CVE-2026-90711 (client address spoofing) | 2.0.8 | No: the flaw is in a trusted-proxy subnet written as an IPv4-mapped IPv6 range. Seerr trusts either no proxy or, with its proxy support on, every proxy, and never sets a subnet | Wait for upstream |

**Notable highs, waiting for upstream:**

- **The other .NET runtime findings** in Lidarr (21), Radarr (16) and Sonarr (7): mostly denial of service over the
  network, plus an ASP.NET Core authentication flaw (CVE-2026-70175) and an authorization one (CVE-2026-50528) in
  Lidarr and Radarr. Reachable through the web UIs and APIs; mitigated by keeping them on the LAN with
  authentication on ([installing.md](installing.md#running-it-securely)). Not reachable: CVE-2025-24070 (Lidarr,
  Sonarr) needs ASP.NET Core Identity's `SignInManager`, which none of the apps uses, and CVE-2026-96225 and
  CVE-2026-96231 need local access to the container.
- **Sonarr v4 runs on .NET 6, out of support since November 2024**, so its count understates it: the scanner only
  reports vulnerabilities whose advisories list .NET 6 as affected, and newer advisories, such as the request
  smuggling above, no longer do. Sonarr's fixes come with v5 (pre-release only so far; Dependabot's major update
  brings it once released).
- **ImageSharp 3.1.11 and 3.1.12** in Lidarr, Radarr and Sonarr (CVE-2026-106110, CVE-2026-106113, CVE-2026-106115;
  54 alerts): not reachable. Two are in its TIFF CCITT encoders and one in histogram equalization; the apps only
  decode posters, resize them and save JPEGs. The fix is ImageSharp 4.1.2, a new major version, and the Servarr
  projects' call.
- **System.Security.Cryptography.Pkcs 8.0.1** in the same three (CVE-2026-84008, denial of service): a library's
  dependency; the apps' own code doesn't use it.
- **Seerr's other 89.** sharp 0.34.5's libvips and libheif (GHSA-f88m-g3jw-g9cj, GHSA-rgj7-g3m4-5g8c) are reachable
  the same way as GHSA-2xp9-vwfh-vxw4 above; its librsvg (GHSA-wq5f-xc86-pv6w) isn't, as the optimizer doesn't
  process SVG. Next.js's CVE-2026-64641, CVE-2026-64642 and CVE-2026-64649 need the App Router, Server Actions or
  middleware, and CVE-2026-64645 a rewrite built from the request: Seerr uses the Pages Router and none of those.
  npm's own packages (`tar`, `pacote`, `sigstore`, `brace-expansion`, …) and the build tools left in the image
  (PostCSS, SVGO, Babel, Browserslist) don't run: npm is only used for `npm start`. multer handles only multipart
  uploads, which Seerr's API doesn't declare. The rest (axios, undici, nodemailer, fast-uri, ip-address, form-data)
  are low: each needs a hostile server among the ones Seerr calls, an outgoing proxy (none unless one is set in
  Seerr), a separate prototype-pollution flaw, or crafted input from a signed-in user.
- **Expat in Recyclarr** (CVE-2026-77214): only git depends on it, to push over HTTP, which Recyclarr never does.
  Fixed with Recyclarr's next image.
- **urllib3 2.7.0 and msgpack 1.1.2** in Bazarr and SABnzbd: low. urllib3's proxy TLS flaw needs an HTTPS proxy,
  and none is configured; its chunk-parser denial of service needs a hostile server among the ones the apps call.
  msgpack crashes only when an `Unpacker` is reused after an error. Fixed in the next linuxserver.io build that
  picks up the new packages.

**Watch: Lidarr.** Its newest stable release (3.1.0.4875, November 2025) still bundles .NET 8.0.12 from January
2025, so CVE-2025-55315 has had a .NET fix for a year that no stable Lidarr release ships. Lidarr's pre-release
builds (3.1.6, .NET 8.0.27) fix it, but not CVE-2026-70188 or CVE-2026-88092. If there's still no stable release
on a newer runtime at the monthly review on 22 November 2026, the maintainer decides between Lidarr's pre-release
builds and staying on the stable one. Until then, keep Lidarr on the LAN with authentication on.

**Watch: Seerr.** It's the one service meant for viewers, so the one most likely to be reachable from beyond the
LAN, and v3.5.1 still ships Next.js 16.2.6. Until a Seerr release ships Next.js 16.3.3 or later, keep Seerr on the
LAN, or behind a reverse proxy with an allow-list, and check again at the same review.

**Watch: Sonarr.** On .NET 6 until v5 is released; checked at the same review.

**Coming with the next scan.** The vulnerability database had grown by 22 October. Besides Bazarr's Pillow (fixed
above), the next weekly scan will report certifi 2026.6.17 in Bazarr and SABnzbd (critical: its bundle trusts an
eMudhra root whose intermediate keys were compromised; reachable only by someone who can intercept the apps'
outgoing HTTPS with such a certificate; fixed in certifi 2026.10.19, in a later linuxserver.io build), the
same `setuptools` and msgpack findings in SABnzbd as in Bazarr, and two in Seerr's follow-redirects 1.16.0
(credential headers kept across a cross-origin redirect; low).

**Earlier triage (7 October 2026),** after the first scan (527 alerts). FlareSolverr (348 alerts, most of them in
its Chromium, the only findings reachable from the internet) was removed: no indexer was configured to use it, and
its newest release still shipped an old Chromium. The unmaintained webnut image (last published in 2015) went the
same day. Bazarr `v1.6.2-ls367` and Recyclarr `8.7.3` fixed 17. Seven alerts were dismissed as not reachable, each
with its reason in code scanning: Bazarr's `setuptools` (`PackageIndex` path traversal; Bazarr never uses
`PackageIndex` or installs packages) and SABnzbd's `PyJWT` (six; installed as a requirement, but nothing in
SABnzbd imports it; only oauthlib does, in code paths SABnzbd's notifications don't use). autoheal and
socket-proxy were added after that scan; autoheal's only maintained tag is `latest` (its versioned tags stop at
1.2.0 from 2021), so it's pinned as `latest@sha256:…` with a policy exception, and bumped by hand with the other
hand-pinned images if Dependabot doesn't propose new digests for it.

## Licenses

homelab-atlas's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff finding fails CI; a
deliberate exception is a per-line `noqa` with the reason next to it.
