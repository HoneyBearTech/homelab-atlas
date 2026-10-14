# homelab-atlas

The Docker Compose stack for Atlas, the owner's homelab media automation server: Recyclarr and the *arr
apps (Radarr and Sonarr with 4K instances, Lidarr, Bazarr, SABnzbd) plus a Dozzle agent and autoheal (behind a socket
proxy), every image pinned by tag and digest so the server can be upgraded and rebuilt from this repository.
homelab-ares is the template for the homelab stacks: tooling that isn't specific to this host's services (checker,
backup scripts, smoke test, workflows) is kept the same as ares'; a change here that isn't about this host's
services goes to ares too (owner's decision 2026-10-13).

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
- No secrets: the apps' API keys, logins and provider credentials stay in their config directories on the host,
  never in `compose.yaml`, `.env` or the `*.example` files. The stack's only secret, autoheal's optional webhook
  URL, comes from the gitignored `autoheal.env` (`env_file`, not required); a new secret gets its own
  `<service>.env` the same way. `.gitignore` covers `.env`, keys,
  `appdata/`, `data/`; extend it rather than work around it. gitleaks runs over the whole history in CI.
- Keep the repo on track for OpenSSF Baseline Levels 1 and 2 and the Best Practices Passing and Silver
  badges. If a change would break a met criterion (for example unpinning an image or an Action, adding a
  workflow without `permissions:`, or dropping the coverage floor), say so before making it.

## Rules for the stack
- **Every image is pinned as `name:tag@sha256:<digest>`.** Never `latest`, never tag-only. Dependabot
  (`docker-compose` ecosystem) updates tag and digest together. linuxserver.io images use their
  `version-<app version>` tag (socket-proxy its bare version), never the `-lsNNN` build tag: Dependabot can't
  follow those. Patch and minor updates (owner's decision 2026-10-06), rebuilds (same tag, new digest, 2026-10-13)
  and major updates (2026-10-14) are auto-merged once the required checks pass (`dependabot-auto-merge.yml`); an
  update Dependabot can't classify waits for the owner. Every merge deploys, the automatic ones included (see
  Deploys), so a major that migrates an app's database one way lands unattended: the nightly backup and a revert
  PR are the way back (a revert alone doesn't undo the migration).
- **No privileged containers, host network/PID, Docker socket mounts or device mappings** unless the
  service carries `org.honeybeartech.atlas.allow.<rule>: "<reason>"` and the owner agreed. **Every service is
  hardened** (`<<: *hardened`: `cap_drop: [ALL]`, `no-new-privileges:true`; the linuxserver.io apps
  `<<: *linuxserver`, which adds back `CHOWN DAC_OVERRIDE SETUID SETGID KILL`); a capability added back must be in
  Docker's default set, carry a comment saying why, and be proven needed (docs/security.md#hardening).
  recyclarr, dozzle (tmpfs `/tmp`), autoheal and socket-proxy (tmpfs `/run`, `/tmp`) run with `read_only: true`;
  the linuxserver.io apps can't (s6-overlay execs from `/run`).
  `scripts/check_compose.py` enforces these rules in CI and in the release workflow.
- **Never change the live server** (atlas) without the owner asking: merges only as **Merging** says, no
  `docker compose up`, no edits to app data or Portainer stacks. Read-only inspection (`docker ps`, `docker inspect`)
  only when asked.
- Every setting goes through `.env` (`${VAR:?…}` in compose when required) and is listed in `.env.example`
  and `docs/interfaces.md`.
- **Container paths are load-bearing**: the apps store `/media/...` paths in their databases (SABnzbd also
  `/incomplete`), so `/media`, `/incomplete`, `/config` and `/scripts` never change. Each app's `/config` is a
  bind-mounted config directory, `${CONFIG_ROOT}/<app>/config` (owner's decision 2026-10-14; named volumes before,
  which atlas keeps until the apps run from the directories); atlas' `CONFIG_ROOT` lives only in its `.env`. Before
  a cutover or redeploy, compare the live containers' mounts and ports with `docker compose config`: atlas has been
  changed by hand before.
- Policy exceptions in use (each agreed by the owner): `dozzle` (`docker-socket`, read-only mount; an agent for
  the homelab's Dozzle hub on another host, port 7007, owner 2026-10-13),
  `socket-proxy` (`docker-socket`: filters the API down to list/inspect/restart/stop for autoheal, internal network,
  no port), `autoheal` (`latest`: the image's only maintained tag). Don't add more without the owner agreeing.
- autoheal restarts every service labelled `autoheal: "true"` that turns unhealthy; every app service carries the
  label. It must never get the socket itself, only `tcp://socket-proxy:2375`.
- Backups (`scripts/backup.sh`, `restore.sh`, `scheduled-backup.sh`, helpers in `scripts/lib.sh`, as in ares)
  archive every read-write volume or bind mount except the Docker socket, anonymous volumes and the mounts a
  service's `org.honeybeartech.atlas.backup.skip` label lists. **Every service that mounts `/media` carries
  `backup.skip: "/media"`** (SABnzbd `"/media,/incomplete"`), so a backup holds only the apps' `/config`,
  Recyclarr's `/config` and Radarr's `/scripts`: a new service or mount gets a skip label unless its data
  belongs in the nightly backup. `org.honeybeartech.atlas.backup.exclude` lists paths inside a mount to leave out
  (comma-separated; the apps' `/config/MediaCover`). Each service is stopped only while its data is copied;
  compression (pigz or gzip) runs after it starts again. `restore.sh` only writes mounts listed in the backup's
  MANIFEST that the service still mounts read-write, never a skipped mount. The nightly run (systemd user timer,
  03:00) copies to the backup server with rsync and keeps 3 here / 30 there (owner's choices 2026-10-13); its
  settings, including the Uptime Kuma push URL, are in the gitignored `backup.env`.

## Deploys (owner's decision 2026-10-14)
- **A merge to `main` deploys.** A pull agent on atlas (systemd user timer `homelab-pull@atlas`, from the owner's
  private homelab-ops repo; rolled out host by host, see Chronos) fetches `main` about every 90 s. When it moved,
  the agent fast-forwards the checkout and runs `docker compose config --quiet`, `docker compose pull` and
  `docker compose up -d --remove-orphans --wait`: a merge is live within about two minutes. It refuses local
  changes and non-fast-forward history, and moves the checkout back if config or pull fails.
- **Backups and restores lock out deploys**: `deploy_lock` in `scripts/lib.sh` (`pull_stack=atlas`, same function
  text as ares) takes the agent's `flock` on `<state dir>/atlas/lock` before anything stops or is created, waits up
  to 30 min for a deploy, and holds it until exit; the agent skips its runs meanwhile. No state dir = no lock (CI,
  the Mac). The smoke test points `HOMELAB_PULL_STATE_DIR` at a directory that doesn't exist.
- **Rollback is a revert PR**, deployed the same way. A revert doesn't undo a data migration: then the backup and
  `scripts/restore.sh` are the way back, with the owner.
- **Pinning by hand**: the owner checks out another commit or tag on the host; the agent pauses until the checkout
  is on `main` again. Release tags stay as signed, verified snapshots; they no longer drive deploys.

## Stack
- Docker Compose v2 (`compose.yaml`, 12 services), upstream images (linuxserver.io where available).
- `scripts/check_compose.py`: Python 3.14, standard library only. Reads `docker compose config --format json`,
  reports policy violations (exit 1), `--sbom FILE` writes a CycloneDX 1.6 SBOM of the images.
- Settings per path/volume/prefix in `.env` (`*_ROOT`, `*_PATH`, `*_VOLUME`, `*_PREFIX`): the smoke test replaces
  each kind with throwaway ones derived from `.env.example`, so keep that naming for new settings.
- `scripts/*.sh`: bash, must also run on macOS' bash 3.2 (no `mapfile`, no associative arrays).
- Tooling: ruff with every rule family (`select = ["ALL"]`, exceptions in `pyproject.toml`; per-line `noqa`
  with a reason) and `ruff format`; yamllint (`.yamllint.yml`); shellcheck (`-x`); pytest + coverage (90 % branch
  floor); pip-tools for the hash-pinned `requirements-dev.txt`. CI-only: actionlint, gitleaks, CodeQL (python,
  actions), Scorecard, dependency review, DCO, Trivy image scan, Dependabot auto-merge (patch/minor/major, rebuilds).
- CI pulls from Docker Hub logged in with a read-only token (`DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`, Actions and
  Dependabot secrets; owner's decision 2026-10-13) when the secrets exist, else anonymously; the smoke job logs
  out before any container starts. The smoke test runs on `ubuntu-24.04` (amd64, like atlas).
- GitLab copy: the owner's self-hosted GitLab (CE, LAN only; host facts in Chronos) is to hold a mirror. GitHub
  stays the home (OpenSSF badges, Scorecard, Dependabot, releases); every change goes to GitHub as a PR, never to
  GitLab. `.gitlab-ci.yml` mirrors GitHub on a schedule (fast-forward only, `MIRROR_TOKEN` CI/CD variable) and
  re-runs the daemon-free checks; the smoke test stays GitHub-only. The owner still has to create the GitLab
  project, the `MIRROR_TOKEN` variable and the schedule; until then the file does nothing.
- Releases (`release.yml`, on a `v*.*.*` tag): policy check, source archive, CycloneDX SBOM, `SHA256SUMS`
  signed with cosign keyless, SLSA provenance (Sigstore bundle + in-toto JSONL), GitHub Release from the
  tag's `CHANGELOG.md` section. No images are built or published.

## Conventions
- `CHANGELOG.md` (Keep a Changelog): add to "Unreleased" with every user-visible change.
- Docs in `docs/` change in the same PR as the behaviour; anything not built yet is marked **Planned**.
- New checker rule → fixture case that triggers it + `test_every_rule_is_reported_exactly` stays exact.
- Workflows: top-level `permissions: contents: read`, raise per job; actions pinned by full SHA with a
  version comment; untrusted `${{ github.event.* }}` only through `env:`.
- `CI / Checks + tests` and `CI / Stack smoke test` are required checks (with DCO, dependency review and
  CodeQL's two analyses); don't rename those jobs.
- **Merging (owner's decision 2026-10-14):** Claude opens a PR for every change. A merge deploys (see Deploys),
  so Claude merges once every required check is green (the owner's standing permission, 2026-10-14) and
  then says that it merged and that it's deploying to atlas. It asks first when the deploy needs something on
  the server (a new `.env` setting, a data migration without a recent good backup, an update this file says
  waits for the owner) or the server isn't healthy, and never turns on auto-merge (`gh pr merge --auto`)
  without the owner's OK. Never bypass a check or the ruleset.
  Dependabot's patch, minor and major updates and rebuilds auto-merge through `dependabot-auto-merge.yml` once
  every required check passes, so they deploy unattended; an update it can't classify waits for the owner.
  Claude never merges a major update itself: majors are merged only by Dependabot's auto-merge or by the owner.
  Keeping that auto-merge is the owner's call: don't change `dependabot-auto-merge.yml` without it.

## Commands
```sh
make test     # checker tests + coverage floor (no Docker, no network)
make lint     # ruff check, ruff format --check, yamllint --strict, shellcheck -x
make check    # docker compose config --format json | scripts/check_compose.py  (needs .env)
make smoke    # scripts/smoke-test.sh: throwaway project, healthy, backup/restore round trip (needs Docker)
make config   # docker compose config (resolved file)
```
Regenerate the dev tools: `pip-compile --generate-hashes --strip-extras requirements-dev.in`, then put the
one-line `# Generated from …` header back.

Release (Claude tags it, owner's decision 2026-10-07): move "Unreleased" into a `## [x.y.z] - date` section of
`CHANGELOG.md` (SemVer; date = the day of tagging) in a PR and merge it once green. Then, with `main` clean and
equal to `origin/main` and CI on that commit green: `git tag -s vX.Y.Z -m vX.Y.Z` (the Mac's SSH signing key),
check it with `git -c gpg.ssh.allowedSignersFile=.github/allowed_signers tag -v vX.Y.Z`, and
`git push origin vX.Y.Z`; `release.yml` does the rest. Tags can't be moved or deleted (ruleset), so tag only
what the owner asked to release. Afterwards verify the release from outside as `docs/verifying-releases.md`
describes (cosign, `SHA256SUMS`, `gh attestation verify`, tag signature, SBOM vs `compose.yaml`).
