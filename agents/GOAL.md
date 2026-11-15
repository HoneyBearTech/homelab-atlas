# Goal

Keep the server's stack pinned, tested, updated automatically and rebuildable from this repository.

What this project is for, as checks. One row for each milestone: what must be true, and the command that proves it, in
backticks. CI runs each command on the main branch (`.github/workflows/goal.yml`), and a milestone is done when its check passes
there. Harness tells the project's PM and its channel how many pass. A command that needs a pipe goes in a script.

| Milestone | Check |
|---|---|
| Every image is pinned by tag and digest and nothing runs privileged | `cp .env.example .env && make check` |
| Lint and unit tests pass | `make lint test` |
| Renovate is set up as docs/dependencies.md describes | `agents/checks/renovate.sh` |
| Optional services are Compose profiles | `agents/checks/profiles.sh` |
| The documented rebuild has an automated rehearsal | `scripts/rehearse-rebuild.sh --list` |
