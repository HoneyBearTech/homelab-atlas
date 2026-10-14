# Security requirements

What homelab-atlas is meant to guarantee, what it leaves to the operator and the apps, and where secrets
live. The reasoning behind these requirements is in the [assurance case](assurance-case.md).

## What homelab-atlas protects

1. **Only reviewed versions run.** Every image is pinned as `name:tag@sha256:<digest>`. A registry tag
   that is moved or hijacked doesn't change what `docker compose pull` fetches; a new version arrives only
   as a pull request that changes the digest.
2. **No container gets more of the host than it needs.** Every service drops every Linux capability, adds back
   only the ones its image needs (never more than Docker's default set) and can't gain privileges from setuid
   binaries or file capabilities. No service runs privileged, shares the host's network or PID namespace, maps a
   host device or mounts the Docker socket (which is root on the host), unless the exception is written into the
   service as a reasoned label and reviewed. Where an image allows it, its root filesystem is read-only
   ([Hardening](#hardening)).
3. **No secrets in the repository.** The apps keep their API keys, logins and provider credentials in
   their own config directories (under `CONFIG_ROOT`), outside the repository. `.env` holds settings only; the
   stack's one secret, autoheal's optional webhook URL, is in `autoheal.env`. Both are gitignored. Secret
   scanning with push protection and a gitleaks scan of the whole history in CI back this up.
4. **No host details in the repository.** It is public: no hostnames, IP addresses, internal domains or
   host paths are committed. Examples use placeholders.
5. **Releases are verifiable.** Release files are listed in a `SHA256SUMS` signed keylessly by the release
   workflow, with SLSA provenance and an SBOM of the pinned images ([verifying-releases.md](verifying-releases.md)).

## Policy

`scripts/check_compose.py` enforces requirements 1 and 2 on the resolved Compose file in CI and before
every release. A service may break a rule only with the label `org.honeybeartech.atlas.allow.<rule>` and a
non-empty reason:

| Rule | Fails when a service |
| --- | --- |
| `image` | has no `image` |
| `digest` | uses an image without both a tag and a `sha256` digest |
| `latest` | uses the `latest` tag |
| `build` | builds an image instead of pulling a pinned one |
| `privileged` | sets `privileged: true` |
| `no-new-privileges` | doesn't set `security_opt: [no-new-privileges:true]` |
| `cap-drop` | doesn't drop every capability (`cap_drop: [ALL]`) |
| `cap-add` | adds a capability outside Docker's default set (adding back one of those only narrows the default) |
| `host-network` / `host-pid` | uses the host's network or PID namespace |
| `docker-socket` | mounts the Docker socket |
| `devices` | maps a host device into the container (a GPU reservation under `deploy.resources` is allowed) |
| `healthcheck` | has no health check, or disables it (one defined only in the image isn't visible to the check) |

## Hardening

What each service runs with, beyond the policy. Every service has `cap_drop: [ALL]` and
`no-new-privileges:true`, and every service whose image allows it has a read-only root filesystem. The smoke test
proves each one still starts healthy with data directories owned by `PUID:PGID` as on a host, survives a backup and
restore, and that autoheal can still restart a container through socket-proxy with these settings.

| Service | Capabilities added back | Read-only root filesystem | Why |
| --- | --- | --- | --- |
| radarr, radarr4k, sonarr, sonarr4k, lidarr, bazarr, bazarr4k, sabnzbd | `CHOWN`, `DAC_OVERRIDE`, `SETUID`, `SETGID`, `KILL` | no | The linuxserver.io init (s6) runs as root: it takes ownership of `/config` and the app's own directories for `PUID:PGID` (`CHOWN`; it must enter directories it doesn't own to do so, `DAC_OVERRIDE`), starts the app as that user (`SETUID`, `SETGID`) and signals it to stop (`KILL`; without it every stop waits for Docker's timeout and kills the app). Their root stays writable: s6-overlay runs its init from `/run`, which a tmpfs mounts without exec, and the init rewrites `/etc/passwd` for `PUID` |
| recyclarr | none | yes (`/tmp` in memory) | Runs as `PUID:PGID` and writes only its config directory, and its crontab to `/tmp` |
| dozzle | none | yes (`/tmp` in memory) | Reads the Docker socket, which belongs to root; writes only its address file to `/tmp` |
| autoheal | none | yes | Only talks to socket-proxy |
| socket-proxy | none | yes (`/run`, `/tmp` in memory) | Only reads the socket |

Each capability was found by starting the image without it: the app then fails to start, can't write its
database, can't repair a `/config` with files owned by another user, or takes 30 seconds to stop and is killed.
Without `CHOWN` and `DAC_OVERRIDE` the apps' root can only reach what it owns.

## What it doesn't protect

- **The apps themselves.** A vulnerability in Radarr, Sonarr or another app is that project's to fix;
  homelab-atlas ships the fixed version once it's released ([dependencies.md](dependencies.md)).
- **Access to the web UIs.** Each app has its own authentication, which the operator must turn on
  ([installing.md](installing.md#running-it-securely)). homelab-atlas doesn't add a reverse proxy, TLS or
  single sign-on.
- **The host.** Anyone with root, `docker` group membership or write access to `.env`, `autoheal.env`, `CONFIG_ROOT`,
  `APPDATA_ROOT`, `RECYCLARR_CONFIG_PATH`, `SABNZBD_INCOMPLETE_PATH` or `MEDIA_ROOT` controls the stack; those are trusted.
- **Media and downloads.** What the apps download is untrusted content from the internet; the apps run as
  an unprivileged user with access to `/media`, which limits but doesn't remove that risk.
- **Dozzle's access to Docker.** The Dozzle agent needs the Docker socket to read logs; read-only mounting
  doesn't limit the Docker API, so any Dozzle that can reach the agent's port, and anyone who can use that
  Dozzle's web UI, can see every container's logs. It is an allowed exception (label in `compose.yaml`); keep its
  port on the LAN.
- **autoheal's reach.** autoheal never holds the socket: `socket-proxy` does (the second allowed exception) and
  passes on only listing, inspecting, restarting and stopping containers, on an internal network with no
  published port. Whoever controls autoheal or the proxy can still stop any container on the host and read
  containers' settings, including their environment; this stack keeps no secrets in environment variables.
- **Restart loops.** autoheal restarts an unhealthy app every few minutes for as long as it stays unhealthy;
  that keeps a hung app available but can hide a real fault. Restarts are logged (and sent to the webhook if one
  is set).
- **Upstream images' internals.** linuxserver.io images start as root and drop to `PUID:PGID`; that is the
  image's design and is accepted.

## Where secrets live

| Secret | Where | Never in |
| --- | --- | --- |
| App API keys, UI logins | each app's config directory (`CONFIG_ROOT/<app>/config`) | the repository, `.env`, issues, logs you paste |
| Usenet provider and indexer credentials | SABnzbd's and the apps' config directories | same |
| Radarr and Sonarr API keys for Recyclarr | `RECYCLARR_CONFIG_PATH` (`recyclarr.yml` or its secrets file) | same |
| autoheal's webhook URL | `autoheal.env` (mode `600`, gitignored) | same |
| The backup's push-monitor URL | `backup.env` (mode `600`, gitignored) | same |
| The backup server's SSH key | `~/.ssh/` on the host, used only for the backup user (`restrict,from=` on the server) | the repository, `.env` |
| Backups of the config directories | off the host, mode `600` | anywhere public |
