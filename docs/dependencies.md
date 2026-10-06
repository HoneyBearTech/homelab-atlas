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
| The stack's images (planned) | `compose.yaml` | version tag and digest | `docker compose pull` |
| Check and test tools (pytest, coverage, ruff, yamllint) | [`requirements-dev.in`](../requirements-dev.in) → [`requirements-dev.txt`](../requirements-dev.txt) | exact version and SHA-256 hashes (`pip-compile --generate-hashes`) | `pip install --require-hashes --no-deps` |
| Linters and scanners used only by CI (actionlint, gitleaks) | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | version tag and digest | Docker |
| GitHub Actions | [`.github/workflows/`](../.github/workflows/) | full commit SHA (version in a comment) | GitHub Actions |

Each release carries a CycloneDX SBOM listing every service's image and digest
([verifying-releases.md](verifying-releases.md)). To update the pinned Python tools, edit
`requirements-dev.in` if needed and run `pip-compile --generate-hashes --strip-extras requirements-dev.in`.

## Tracking dependencies

- **Dependabot** ([`.github/dependabot.yml`](../.github/dependabot.yml)) checks weekly for new image
  versions in the Compose file, new tool versions and new Action versions, and opens a pull request for
  each. Dependabot alerts and security updates are on.
- **Every update is merged by hand.** An image bump can migrate an app's database, so the maintainer reads
  the app's release notes first; none are auto-merged.
- **Dependency review** ([`.github/workflows/dependency-review.yml`](../.github/workflows/dependency-review.yml))
  blocks a pull request that adds or changes a Python or Actions dependency with a known vulnerability of
  moderate severity or higher, or a license outside the allowlist.
- The CI-only images in `run:` steps aren't seen by Dependabot; they're bumped by hand at least every
  quarter.
- **Nothing updates itself on the host.** Auto-updaters such as Watchtower are not used: they would run
  versions nobody reviewed.

## Policy for vulnerabilities in dependencies

Known vulnerabilities are found through Dependabot alerts, the apps' and images' own advisories, and
(planned) a scheduled image scan of the pinned digests. Each finding is triaged within 14 days:

1. **If a fixed version exists**, bump to it (a Dependabot pull request usually already does) and release.
   A fix for an exploitable critical or high-severity vulnerability goes out in a patch release within 30
   days; others go out with the next release.
2. **If upstream hasn't released a fix**, assess whether it's reachable in this stack (which ports are
   published, what the app does with untrusted input). If it is, mitigate it where possible (for example,
   stop publishing a port) and say so in the release notes; otherwise record the reason when dismissing
   the alert. Either way, it's fixed by a bump when upstream ships one.
3. **If an image is abandoned** and keeps accumulating vulnerabilities, replace it.

No findings are open as of 6 October 2026.

## Licenses

homelab-atlas's own files are MIT-licensed. The Python tools must be under an OSI-approved license that
dependency review allows (MIT, Apache-2.0, BSD, ISC, PSF, MPL-2.0 and similar); yamllint (GPL-3.0) is
allowed as a development tool. The images keep their own licenses.

## Policy for findings from static analysis (SAST)

CodeQL analyses the checker and the workflows on every pull request and weekly, and ruff runs the bandit
security rules in CI. A CodeQL finding of medium severity or higher is fixed before the next release, or,
if it is a false positive, dismissed in code scanning with a written reason. A ruff finding fails CI; a
deliberate exception is a per-line `noqa` with the reason next to it.
