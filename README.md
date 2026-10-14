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

## Documentation

- [Quick start](docs/quick-start.md): getting the stack running on a fresh Docker host
- [Installing](docs/installing.md): host preparation, directory layout, running it securely, uninstalling
- [Upgrading](docs/upgrading.md): moving to a new release, backup and restore, rolling back
- [Rebuilding](docs/rebuilding.md): a new or wiped host, from a backup
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

Radarr and Sonarr (regular and 4K instances), Lidarr, Bazarr (regular and 4K), SABnzbd and Recyclarr, plus
a Dozzle agent (container logs, for the homelab's Dozzle) and autoheal (restarts an app that turns unhealthy), all from their upstream images ([architecture](docs/architecture.md),
ports in [interfaces](docs/interfaces.md#services-and-ports)). The indexer manager, the torrent client and the
media server run on other hosts.

Every image is pinned by tag **and** digest. New versions arrive as Dependabot pull requests that CI checks
before they're merged. The maintainer's server follows `main`: a pull agent there applies each merge within a couple
of minutes ([upgrading](docs/upgrading.md#following-main)). Nothing updates from a registry tag by itself: what runs
is always a commit in `main`.

## Getting started

```sh
git clone https://github.com/HoneyBearTech/homelab-atlas.git && cd homelab-atlas
cp .env.example .env && chmod 600 .env              # then set PUID/PGID, TZ, MEDIA_ROOT, ...
docker compose up -d
```

The full steps, including creating the directories with the right owner, are in the
[quick start](docs/quick-start.md).

## Usage

```sh
docker compose ps                 # what's running
docker compose logs -f <service>  # one app's log
make check                        # policy check: every image pinned, nothing privileged
scripts/backup.sh                 # back up every app's config (each app stops briefly)
```

Upgrading to a new release, or following `main` the way the maintainer's server does:
[docs/upgrading.md](docs/upgrading.md).

## Configuration

Settings come from `.env` (template [`.env.example`](.env.example)), which holds no secrets.

| Setting | Default in `.env.example` | Meaning |
| --- | --- | --- |
| `PUID`, `PGID` | `1000` | User and group the apps run as; must be able to write `MEDIA_ROOT` and `RECYCLARR_CONFIG_PATH` |
| `TZ` | `Etc/UTC` | Time zone |
| `UMASK` | `002` | File creation mask inside the linuxserver.io apps |
| `MEDIA_ROOT` | `/srv/media` | Downloads and media on one filesystem (`/media`), so imports are hardlinks or instant moves |
| `APPDATA_ROOT` | `/srv/appdata` | Radarr's custom scripts (`radarr/scripts`, `radarr4k/scripts`) |
| `CONFIG_VOLUME_PREFIX` | `homelab-atlas_` | Prefix of the Docker volumes holding each app's config and database. Contains API keys: back them up |
| `SONARR4K_CONFIG_VOLUME` | empty | Optional: Sonarr 4K's volume name, when it doesn't follow the prefix |
| `SABNZBD_INCOMPLETE_PATH` | `/srv/downloads/incomplete` | SABnzbd's temporary download folder (`/incomplete`); may be another disk |
| `RECYCLARR_CONFIG_PATH` | `/srv/appdata/recyclarr` | Recyclarr's config directory |

Ports, volumes and labels: [docs/interfaces.md](docs/interfaces.md).

## Running it securely

- Turn on each app's authentication before anything else, and keep the web UIs on your LAN. Docker-published
  ports bypass host firewalls such as `ufw`.
- Secrets (API keys, logins, provider credentials) live only in each app's config volume, never in this
  repository or `.env`.
- The Dozzle agent reads logs through the Docker socket: keep its port (7007) on the LAN. autoheal never gets
  the socket: it goes through a proxy that only lets it list, restart and stop containers.
- autoheal's optional webhook URL (restart notices, for example to Discord) goes in `autoheal.env` (template
  [`autoheal.env.example`](autoheal.env.example), mode `600`, gitignored).
- Don't run an auto-updater such as Watchtower on these containers; upgrade from this repository instead (a
  release, or `main`).
- Every service drops all Linux capabilities and runs with `no-new-privileges`; the linuxserver.io apps add back
  only the few their init needs. The policy check enforces that and refuses privileged containers, capabilities
  beyond Docker's defaults, host networking, device mappings and Docker socket mounts unless a service documents
  why ([docs/security.md](docs/security.md#hardening)).

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
