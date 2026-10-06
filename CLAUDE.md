# homelab-atlas

The Docker Compose stack for Atlas, the owner's homelab media automation server: Recyclarr and the *arr
apps (Radarr and Sonarr with 4K instances, Lidarr, Bazarr, SABnzbd, FlareSolverr) plus Dozzle and webnut,
every image pinned by tag and digest so the server can be upgraded and rebuilt from this repository.

## Before Making Structural Changes
Read the project's notes first. They live outside this repo, in the owner's Obsidian vault **Chronos** at
`~/Chronos/Projects/homelab-atlas/` (every file is prefixed `homelab-atlas-`):
- `homelab-atlas-roadmap.md`: phases with checkboxes, including the OpenSSF phase and the owner's manual
  GitHub steps
- `homelab-atlas-Pass-Map.md`: pass-by-pass delivery log; add a row when a pass ships
- `homelab-atlas-Architecture.md`: the host, which containers run there today and which belong in this repo,
  data flow, deployment shape
- `homelab-atlas-Security-Considerations.md`: assets, threats, trust boundaries, checklist (Atlas holds every
  app's API keys and write access to the media library: treat these notes as load-bearing)
- `homelab-atlas-Decisions-Log.md`: ADR-style log (entries marked **Proposed** still need the owner's call)

Keep them current as work lands: tick roadmap checkboxes, add a Pass-Map row per pass, add dated
Decisions-Log entries. **The notes never go into this repo.** Chronos is versioned in its own private repo;
only commit or push it when the owner asks. The old in-repo vault path `.obsidian-docs/` stays gitignored.

## This repo is public
- No hostnames, IP addresses, internal domains, host paths, Portainer stack names or personal email
  addresses in anything committed: code, compose, docs, examples, tests, commit messages. Host facts live
  only in the Chronos notes. Examples use placeholders (`/srv/appdata`, `/srv/media`, `homelab-atlas_`).
- Commit as `31805425+HoneyBearTech@users.noreply.github.com` (set as this repo's `user.email`), with
  `git commit -s` for the DCO sign-off; commits and tags are SSH-signed.
- No secrets: the apps' API keys, logins and provider credentials stay in their config volumes on the host,
  never in `compose.yaml`, `.env` or the `*.example` files. The only secret the stack reads, webnut's UPS
  login, comes from the gitignored `webnut.env` (`env_file`); a new secret gets its own `<service>.env` the
  same way. `.gitignore` covers `.env`, keys, `appdata/`, `data/`; extend
  it rather than work around it. gitleaks runs over the whole history in CI.
- Keep the repo on track for OpenSSF Baseline Levels 1 and 2 and the Best Practices Passing and Silver
  badges. If a change would break a met criterion (for example unpinning an image or an Action, adding a
  workflow without `permissions:`, or dropping the coverage floor), say so before making it.

## Rules for the stack
- **Every image is pinned as `name:tag@sha256:<digest>`.** Never `latest`, never tag-only. Dependabot
  (`docker-compose` ecosystem) updates tag and digest together; image bumps are merged by hand, never
  auto-merged (an app may migrate its database).
- **No privileged containers, added capabilities, host network/PID or Docker socket mounts** unless the
  service carries `org.honeybeartech.atlas.allow.<rule>: "<reason>"` and the owner agreed.
  `scripts/check_compose.py` enforces both rules in CI and in the release workflow.
- **Never change the live server** (atlas) without the owner asking: no `docker compose up`, no edits to
  app data or Portainer stacks. Read-only inspection (`docker ps`, `docker inspect`) only when asked.
- Every setting goes through `.env` (`${VAR:?…}` in compose when required) and is listed in `.env.example`
  and `docs/interfaces.md`.
- **Container paths are load-bearing**: the apps store `/media/...` paths in their databases, so `/media`,
  `/config` and `/scripts` never change. Config volumes are named `${CONFIG_VOLUME_PREFIX}<app>` so atlas keeps
  its existing (Portainer-created) volumes; the prefix lives only in atlas' `.env`.
- Policy exceptions in use: `dozzle` (`docker-socket`, read-only mount), `webnut` (`latest`: the image has no
  other maintained tag). Don't add more without the owner agreeing.

## Stack
- Docker Compose v2 (`compose.yaml`, 12 services), upstream images (linuxserver.io where available).
- `scripts/check_compose.py`: Python 3.14, standard library only. Reads `docker compose config --format json`,
  reports policy violations (exit 1), `--sbom FILE` writes a CycloneDX 1.6 SBOM of the images.
- Tooling: ruff with every rule family (`select = ["ALL"]`, exceptions in `pyproject.toml`; per-line `noqa`
  with a reason) and `ruff format`; yamllint (`.yamllint.yml`); pytest + coverage (90 % branch floor);
  pip-tools for the hash-pinned `requirements-dev.txt`. CI-only: actionlint, gitleaks, CodeQL (python,
  actions), Scorecard, dependency review, DCO.
- Releases (`release.yml`, on a `v*.*.*` tag): policy check, source archive, CycloneDX SBOM, `SHA256SUMS`
  signed with cosign keyless, SLSA provenance (Sigstore bundle + in-toto JSONL), GitHub Release from the
  tag's `CHANGELOG.md` section. No images are built or published.

## Conventions
- `CHANGELOG.md` (Keep a Changelog): add to "Unreleased" with every user-visible change.
- Docs in `docs/` change in the same PR as the behaviour; anything not built yet is marked **Planned**.
- New checker rule → fixture case that triggers it + `test_every_rule_is_reported_exactly` stays exact.
- Workflows: top-level `permissions: contents: read`, raise per job; actions pinned by full SHA with a
  version comment; untrusted `${{ github.event.* }}` only through `env:`.
- `CI / Checks + tests` is the required check name; don't rename the job.

## Commands
```sh
make test     # checker tests + coverage floor (no Docker, no network)
make lint     # ruff check, ruff format --check, yamllint --strict
make check    # docker compose config --format json | scripts/check_compose.py  (needs .env and webnut.env)
make config   # docker compose config (resolved file)
```
Regenerate the dev tools: `pip-compile --generate-hashes --strip-extras requirements-dev.in`, then put the
one-line `# Generated from …` header back.

Release (the owner does this): add a `## [x.y.z] - date` section to `CHANGELOG.md`, then
`git tag -s vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`; `release.yml` does the rest.
