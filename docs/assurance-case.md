# Assurance case

Why homelab-atlas meets its [security requirements](security.md): the threat model, the trust boundaries,
the secure design principles it follows, and how common weaknesses are countered.

## Threat model

| Asset | Threat | Countered by |
| --- | --- | --- |
| The host | A compromised or malicious image | Digest pins; versions change only by reviewed pull request; no privileged, capability, host-namespace or socket access without a reasoned label |
| The host | A container breaking out through the Docker socket | The `docker-socket` rule; only Dozzle mounts it, as a labelled exception with its UI kept on the LAN |
| App API keys and credentials | Committed to the public repository | Kept in the apps' config volumes, never in the repo; `.gitignore`; gitleaks over the history in CI; GitHub push protection |
| App API keys and credentials | Leaked through a backup | Backups documented as secret (mode `600`, off the host) |
| The media library | A compromised app deleting or encrypting it | Apps run as `PUID:PGID`, not root; storage-level snapshots recommended ([upgrading.md](upgrading.md#backing-up)) |
| The app databases | An upgrade that migrates and breaks them | Backup before every upgrade; rollback = old tag + restored backup |
| The release | Tampered release files | Keyless-signed `SHA256SUMS`, SLSA provenance, signed tags |
| The CI pipeline | Untrusted pull request input running with credentials | `pull_request` only, read-only token by default, untrusted values only via `env:`, actions pinned by SHA |
| Operator privacy | Hostnames, addresses or paths in the public repo | Placeholders only; reviewed in every pull request |

Attackers considered: a compromised upstream image or registry tag; someone on the LAN reaching an app's
web UI; a malicious pull request; a malicious download. Out of scope: an attacker who already has root or
`docker` group access on the host, or write access to `.env` or the data directories.

## Trust boundaries

1. **Registries → host.** Images are trusted only at the digest a reviewed commit names.
2. **Repository → host.** The host runs a tagged, signed release or a reviewed `main`; it never pulls code
   that wasn't merged.
3. **LAN → apps.** Each web UI is behind the app's own authentication; anything beyond the LAN needs the
   operator's reverse proxy.
4. **Containers → host.** Only the config volumes, `MEDIA_ROOT`, Radarr's scripts and Recyclarr's config are
   mounted; no host namespaces. The one socket mount (Dozzle, read-only) is a reviewed, labelled exception.
5. **Internet → apps.** Indexer results and downloads are untrusted data handled by the apps.
6. **Pull requests → CI.** Fork pull requests get a read-only token and no secrets.

## Secure design principles

- **Least privilege**: unprivileged app users, no added capabilities, read-only CI tokens raised per job.
- **Fail-safe defaults**: the policy check fails on anything it doesn't recognise as allowed; an exception
  needs a reason, in the file, in review.
- **Complete mediation**: every change to what runs passes through a pull request and the same checks;
  nothing on the host updates itself.
- **Economy of mechanism**: one Compose file, one standard-library checker, upstream images unchanged.
- **Separation of privilege**: secrets live with the apps, settings in `.env`, configuration in git.
- **Open design**: the whole configuration, policy and release process are public.

## Common weaknesses

| Weakness | Where it could arise | How it's countered |
| --- | --- | --- |
| CWE-494 (code downloaded without integrity check) | Image pulls | Digest pins; signed release checksums |
| CWE-798 / CWE-312 (hard-coded or cleartext credentials) | Compose `environment:`, `.env`, docs | No secrets in the repo; gitleaks; push protection |
| CWE-250 (unnecessary privileges) | Container settings | Policy rules `privileged`, `cap-add`, `host-*`, `docker-socket` |
| CWE-1104 (unmaintained third-party components) | Images, tools, Actions | Dependabot weekly; triage SLAs ([dependencies.md](dependencies.md)) |
| CWE-77/78 (injection) | Workflows | Untrusted values only via `env:`; actionlint with shellcheck; CodeQL for Actions |
| CWE-20 (improper input validation) | The checker's input | It reads JSON only with the standard library, never evaluates it, and exits 2 on anything that isn't a JSON object |

## Evidence

- CI on every change: ruff (with the bandit rules), yamllint, actionlint, gitleaks over the history,
  shellcheck, pytest with a 90 % branch-coverage floor, `docker compose config`, the policy check, and a
  smoke test that starts every pinned image and waits for its health check (a dynamic test of the stack).
- CodeQL (Python and Actions) on every pull request and weekly; OpenSSF Scorecard weekly; dependency
  review on every pull request.
