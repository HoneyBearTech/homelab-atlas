# homelab-atlas

[![CI](https://github.com/HoneyBearTech/homelab-atlas/actions/workflows/ci.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-atlas/actions/workflows/ci.yml)
[![CodeQL](https://github.com/HoneyBearTech/homelab-atlas/actions/workflows/codeql.yml/badge.svg)](https://github.com/HoneyBearTech/homelab-atlas/actions/workflows/codeql.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/HoneyBearTech/homelab-atlas/badge)](https://scorecard.dev/viewer/?uri=github.com/HoneyBearTech/homelab-atlas)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/15265/badge)](https://www.bestpractices.dev/projects/15265)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/15265/baseline)](https://www.bestpractices.dev/projects/15265)

Docker Compose stack for Atlas, the homelab media automation server running Recyclarr and the *arr stack. Ubuntu + Docker, version-pinned for easy upgrades and rebuilds.

> [!WARNING]
> The apps in this stack rename, move and delete files in your media library, and an upgrade can migrate
> their databases irreversibly. Back up the app data before every upgrade ([docs/upgrading.md](docs/upgrading.md)).

> [!NOTE]
> **Work in progress.** The repository has its tooling, policy and docs; the services themselves
> (`compose.yaml`) are being moved in next. Anything not built yet is marked **Planned** in the docs.

## Documentation

- [Quick start](docs/quick-start.md): getting the stack running on a fresh Docker host
- [Installing](docs/installing.md): host preparation, directory layout, running it securely, uninstalling
- [Upgrading](docs/upgrading.md): moving to a new release, backup and restore, rolling back
- [Architecture](docs/architecture.md): the services, actors, data flow and how updates reach the host
- [Interfaces](docs/interfaces.md): every setting, port, volume, label and command
- [Verifying releases](docs/verifying-releases.md): checking signatures, checksums, provenance and the SBOM
- [Security requirements](docs/security.md): what the stack protects, what it doesn't, where secrets live
- [Assurance case](docs/assurance-case.md): threat model, trust boundaries, secure design, common weaknesses
- [Dependencies](docs/dependencies.md): how images and tools are chosen, pinned, tracked and patched
- [Roadmap](docs/roadmap.md): the next year, and what homelab-atlas will not do
- Project policies: [CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · [GOVERNANCE](GOVERNANCE.md) ·
  [SUPPORT](SUPPORT.md) · [CODE OF CONDUCT](CODE_OF_CONDUCT.md) · [CHANGELOG](CHANGELOG.md)

## What's in the stack

**Planned** ([architecture](docs/architecture.md)): Radarr and Sonarr (regular and 4K instances), Lidarr,
Bazarr (regular and 4K), SABnzbd, FlareSolverr and Recyclarr, from their upstream images. The indexer
manager and the media server run on other hosts.

Every image is pinned by tag **and** digest. New versions arrive as Dependabot pull requests that CI checks
and the maintainer merges; nothing on the host updates itself.

## Getting started

```sh
git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
cp .env.example .env && chmod 600 .env    # then set PUID/PGID, TZ, APPDATA_ROOT, DATA_ROOT
docker compose up -d                       # Planned: needs compose.yaml
```

The full steps, including creating the directories with the right owner, are in the
[quick start](docs/quick-start.md).

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one app's log
make check                        # policy check: every image pinned, nothing privileged
```

Upgrading to a new release: [docs/upgrading.md](docs/upgrading.md).

## Configuration

Settings come from `.env` (template [`.env.example`](.env.example)); it holds no secrets.

| Setting | Default in `.env.example` | Meaning |
| --- | --- | --- |
| `PUID`, `PGID` | `1000` | User and group the apps run as; must own both directories below |
| `TZ` | `Etc/UTC` | Time zone |
| `UMASK` | `002` | File creation mask inside the apps |
| `APPDATA_ROOT` | `/srv/appdata` | Each app's config and database (`/config`). Contains API keys: back it up, keep it private |
| `DATA_ROOT` | `/srv/data` | Downloads and media on one filesystem (`/data`), so imports are hardlinks or instant moves |

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Turn on each app's authentication before anything else, and keep the web UIs on your LAN. Docker-published
  ports bypass host firewalls such as `ufw`.
- Secrets (API keys, logins, provider credentials) live only in each app's data under `APPDATA_ROOT`, never
  in this repository or `.env`.
- Don't run an auto-updater such as Watchtower on these containers; upgrade by release instead.
- The policy check refuses privileged containers, added capabilities, host networking and Docker socket
  mounts unless a service documents why ([docs/security.md](docs/security.md)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
