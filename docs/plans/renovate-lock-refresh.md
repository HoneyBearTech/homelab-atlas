# Plan: stop Renovate's lock-file refresh from skipping the three-day wait

**What the owner asked for:** "fix atlas too" (the gap found while moving homelab-hyperion to Renovate).

## What we found

- Renovate's pip-compile manager turns on a periodic lock-file refresh by default. `.github/renovate.json5` doesn't
  turn it off.
- A refresh re-runs pip-compile for the whole of `requirements-dev.txt`, which picks the newest version of every tool.
  It has no release dates, so it skips the three-day wait, and like every update here it merges by itself once the
  required checks pass. A tool released hours earlier could land that way.
- homelab-hyperion's review found this; hyperion turns the refresh off (#75).

## What we'll change

1. **`.github/renovate.json5`:** turn the pip-compile lock-file refresh off, with a comment saying why. The tools keep
   moving one at a time through ordinary updates, which wait three days.
   *Check:* Renovate's config validator in strict mode, and Renovate's resolved config shows the refresh off.
2. **`docs/dependencies.md`:** one sentence saying the whole-file refresh is off and why.
3. **`CHANGELOG.md`:** a short entry under Unreleased.
4. **Job notes:** `docs/pass-map.md` and `docs/decisions-log.md`.

Nothing in `.github/workflows` changes.

## Who's on it

Engineer, Security Officer, Auditor. No Researcher or QA: it's a one-setting change, and the Auditor checks it in
Renovate itself.

## Risks

- Indirect dependencies of the tools now move only when a tool update re-locks the file, as they did before
  pip-compile was adopted (#119).

## Out of scope

Any other Renovate behaviour.
