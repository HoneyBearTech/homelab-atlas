# Plan: work the four open issues (#109, #110, #111, #112)

## What was asked

Sean: "work all open issues in homelab-atlas". The four issues were assigned on 15 November by the repo's own
coordinator, but nothing has been started since; this job takes them over. Each becomes its own pull request.

## What we found

- **#111:** `pyproject.toml` sets ruff's `target-version = "py314"` while CI runs Python 3.15. The pinned ruff
  (0.17.5) accepts `py315`.
- **#110:** `requirements-dev.txt` starts with a custom header line, so Renovate's `pip-compile` manager can't
  read the command; Renovate bumps each pin in place and a new dependency of a tool still needs a hand-run
  `pip-compile`.
- **#112:** `scripts/smoke-test.sh` and `scripts/rehearse-rebuild.sh` both load `scripts/lib.sh` already, but each
  still has its own copy of the free address range, the settings and the per-service overrides.
- **#109:** `willfarrell/autoheal` is built on Alpine 3.18 (end of life). Upstream pins `ALPINE_VERSION=3.18`,
  hasn't committed since September 2025 and hasn't answered the open "update the base image" issue. Of the
  alternatives, `tmknight/docker-autoheal` 0.14.1 (5 November 2026, Alpine 3.24, versioned tags, Rust) does the same
  job and was proven end to end through this stack's socket-proxy pin, hardened, read-only and as a non-root user:
  it restarted only the labelled unhealthy container and posted the Discord-style webhook. `qmcgaw/deunhealth` was
  rejected (it needs Docker's events API, has no webhook or stop timeout and no release since 2021).

## What we'll change

1. **#111, ruff's target.** `pyproject.toml`: `target-version = "py315"`. Check: `make lint test`.
2. **#110, Renovate re-locks the dev tools.** Give `requirements-dev.txt` pip-compile's standard header (same
   command: `--generate-hashes --strip-extras`); enable Renovate's `pip-compile` manager for
   `requirements-dev.in` -> `requirements-dev.txt` in `.github/renovate.json5`, with hashes kept and the in-place
   `pip_requirements` bumps of that file turned off so updates aren't proposed twice; say so in
   `docs/dependencies.md`. Check: Renovate's config validator, a local Renovate dry run that shows the pip-compile
   manager picking the file up, `make lint test`.
3. **#112, one copy of the throwaway-stack setup.** Move the free address range, the settings and the per-service
   overrides that both scripts repeat into `scripts/lib.sh`; both scripts use it, with no change in what they do.
   Check: shellcheck, and both the "Stack smoke test" and the rebuild rehearsal pass in CI.
4. **#109, replace autoheal.** In `compose.yaml`:
   - autoheal's image becomes `ghcr.io/tmknight/docker-autoheal:0.14.1` pinned by digest (no more `latest`
     exception), run as `user: "65534:65534"`, still read-only, hardened and behind the socket proxy, with its
     settings renamed to the new image's names (TCP host and port, interval 10 s, stop timeout 30 s, webhook key
     `content`);
   - the socket proxy also answers `GET /info` (`INFO: 1`), which the new image reads once at start and can't run
     without. It is read-only daemon information; nothing else is added;
   - the opt-in label on each of the 13 services that carry it changes from `autoheal: "true"` to
     `autoheal.monitor.enable: "true"`;
   - `scripts/smoke-test.sh`'s autoheal step uses the new label and the new log line;
   - `docs/security.md` records the comparison and the choice, and `docs/dependencies.md`, `autoheal.env.example`
     and `docs/upgrading.md` cover the change, including the one manual step below.
   Check: the label count before and after, `make lint test` (the compose policy check) and CI's smoke test, which
   makes a container unhealthy and checks autoheal restarts it through the proxy.
5. Record the job in `docs/` (pass map, decisions log, roadmap).

## Who's on it

Researcher (done, for #109), Engineers, QA, Security Officer, Auditor.

## Risks

- **One manual step on the server after #109 merges:** the webhook setting in the gitignored `autoheal.env` is
  renamed from `WEBHOOK_URL` to `AUTOHEAL_WEBHOOK_URL`. Until it is, restarts still happen but no notice is posted.
  The webhook message now starts with the Docker host's name.
- The proxy's allowed calls grow by one read-only call (`GET /info`).
- A service that misses the label rename silently stops being healed; the count check guards against that.
- tmknight's image is GPL-3.0 (run unmodified, noted in `docs/dependencies.md`) and has one maintainer, like the
  image it replaces.
- Merging #109 or #112 deploys at once. #109 restarts every monitored app once, because the label change
  recreates their containers (corrected after review; the first version of this plan said only autoheal and the
  socket proxy restart).

## Out of scope

The other stacks that also run `willfarrell/autoheal`; workflows and branch rules.
