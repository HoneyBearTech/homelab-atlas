"""scripts/backup.sh refuses to run while COMPOSE_PROFILES is missing or mistyped, and the scheduled backup fails then.

Compose ignores a name in COMPOSE_PROFILES that isn't a profile, and stops managing (without stopping) the containers
of a profile left out. A backup of the services Compose runs would then leave their data out and still succeed, and
the scheduled backup's rotation would delete the last complete backups within a few nights. Each test runs the script
against tests/fake_docker.py with a stack of a core service (`radarr`) and two optional ones (`lidarr` in `music`,
`seerr` in `requests`), each with a container unless the test removes it.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
FAKE = Path(__file__).parent / "fake_docker.py"
BASH = shutil.which("bash") or "/bin/bash"
PROFILE_OF = {"lidarr": "music", "seerr": "requests"}


class Stack:
    """The fake stack's state, and the scripts run against it."""

    def __init__(self, tmp_path: Path, **state: object) -> None:
        self.tmp = tmp_path
        self.file = tmp_path / "state.json"
        services = {name: {"state": "running"} for name in ("radarr", "lidarr", "seerr")}
        stack = {"services": services, "profile_of": PROFILE_OF, "fail_stop": {}, "fail_start": [], "log": []}
        self.file.write_text(json.dumps({**stack, **state}), encoding="utf-8")
        bin_dir = tmp_path / "bin"
        bin_dir.mkdir()
        docker = bin_dir / "docker"
        docker.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKE}" "$@"\n', encoding="utf-8")
        docker.chmod(0o755)
        (tmp_path / "empty.env").touch()
        self.env = {
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "HOME": "/nonexistent",
            "FAKE_DOCKER_STATE": str(self.file),
            "HOMELAB_PULL_STATE_DIR": str(tmp_path / "homelab-pull"),
            "COMPOSE_ENV_FILES": str(tmp_path / "empty.env"),
        }

    def run(self, script: str, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        # S603: fixed argv, no shell.
        return subprocess.run(  # noqa: S603
            [BASH, str(ROOT / "scripts" / script), *args],
            env={**self.env, **env},
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )

    def log(self) -> list[str]:
        return json.loads(self.file.read_text(encoding="utf-8"))["log"]


def error(result: subprocess.CompletedProcess[str]) -> str:
    return " ".join(result.stderr.split())


def backup_of(path: Path, services: tuple[str, ...], env: str | None) -> Path:
    """A backup directory as scripts/backup.sh writes it, with env/.env holding `env` (none: no .env)."""
    (path / "env").mkdir(parents=True)
    if env is not None:
        (path / "env" / ".env").write_text(env, encoding="utf-8")
    manifest = "# archive\tservice\tmount\tsource\timage\n"
    for service in services:
        (path / f"{service}--config.tar.gz").write_bytes(b"an archive")
        manifest += f"{service}--config.tar.gz\t{service}\t/config\t/srv/{service}/config\texample/{service}:1\n"
    (path / "MANIFEST").write_text(manifest, encoding="utf-8")
    sums = "".join(
        f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.relative_to(path)}\n"
        for file in sorted(path.rglob("*"))
        if file.is_file()
    )
    (path / "SHA256SUMS").write_text(sums, encoding="utf-8")
    return path


def test_backup_refuses_a_name_that_isnt_a_profile(tmp_path: Path) -> None:
    stack = Stack(tmp_path, compose_profiles="music, musik ,requests")
    result = stack.run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 1, result.stderr
    assert "isn't a profile in compose.yaml: musik (its profiles: music requests)" in error(result)
    assert "Fix COMPOSE_PROFILES in .env" in error(result)
    assert "no backup taken; nothing was stopped" in error(result)
    assert not (tmp_path / "backup").exists()
    assert stack.log() == []


def test_backup_refuses_while_a_profile_with_containers_is_off(tmp_path: Path) -> None:
    stack = Stack(tmp_path)  # COMPOSE_PROFILES not set: only radarr runs
    result = stack.run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 1, result.stderr
    message = error(result)
    assert "whose profile isn't on are here: lidarr (music) seerr (requests)" in message
    assert "COMPOSE_PROFILES is empty or not set" in message
    assert "(every profile: COMPOSE_PROFILES=music,requests)" in message
    assert "docker compose rm --stop --force lidarr seerr" in message
    assert not (tmp_path / "backup").exists()
    assert stack.log() == []


def test_a_typo_leaves_a_profile_off_and_is_caught_too(tmp_path: Path) -> None:
    # Only the name check would catch "musik" if lidarr had no container; with one, both say what's wrong.
    stack = Stack(tmp_path, compose_profiles="musik,requests")
    result = stack.run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 1, result.stderr
    assert "musik" in error(result)
    assert stack.log() == []


def test_backup_runs_with_every_profile_on(tmp_path: Path) -> None:
    stack = Stack(tmp_path, compose_profiles="music,requests")
    result = stack.run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 0, result.stderr
    manifest = (tmp_path / "backup" / "MANIFEST").read_text(encoding="utf-8")
    assert {line.split("\t")[1] for line in manifest.splitlines()[1:]} == {"radarr", "lidarr", "seerr"}


def test_backup_runs_with_every_profile_named_by_star(tmp_path: Path) -> None:
    result = Stack(tmp_path, compose_profiles="*").run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 0, result.stderr


def test_backup_runs_once_the_containers_of_a_profile_turned_off_are_gone(tmp_path: Path) -> None:
    stack = Stack(tmp_path, compose_profiles="requests", containers=["radarr", "seerr"])
    result = stack.run("backup.sh", str(tmp_path / "backup"))
    assert result.returncode == 0, result.stderr
    manifest = (tmp_path / "backup" / "MANIFEST").read_text(encoding="utf-8")
    assert {line.split("\t")[1] for line in manifest.splitlines()[1:]} == {"radarr", "seerr"}


def test_scheduled_backup_fails_and_keeps_the_old_backups(tmp_path: Path) -> None:
    stack = Stack(tmp_path)
    backups = tmp_path / "backups"
    old = ["20200101-000000", "20200102-000000", "20200103-000000"]
    for name in old:
        (backups / name).mkdir(parents=True)
    (tmp_path / "backup.env").write_text(f"BACKUP_DIR={backups}\nBACKUP_KEEP=1\n", encoding="utf-8")
    result = stack.run("scheduled-backup.sh", BACKUP_ENV_FILE=str(tmp_path / "backup.env"))
    assert result.returncode == 1, result.stderr
    assert "whose profile isn't on" in error(result)
    assert sorted(path.name for path in backups.iterdir()) == old
    assert stack.log() == []


def test_restore_refuses_a_name_that_isnt_a_profile(tmp_path: Path) -> None:
    stack = Stack(tmp_path, compose_profiles="music,musik,requests")
    backup = backup_of(tmp_path / "backup", ("radarr",), "COMPOSE_PROFILES=music,requests\n")
    result = stack.run("restore.sh", "--yes", str(backup))
    assert result.returncode == 1, result.stderr
    assert "isn't a profile in compose.yaml: musik" in error(result)
    assert "nothing changed" in error(result)
    assert stack.log() == []


def test_restore_of_a_backup_from_before_the_profiles_says_to_turn_on_every_profile(tmp_path: Path) -> None:
    stack = Stack(tmp_path, compose_profiles="requests")
    backup = backup_of(tmp_path / "backup", ("radarr", "lidarr", "seerr"), "PUID=1000\n")
    result = stack.run("restore.sh", "--yes", str(backup))
    assert result.returncode == 1, result.stderr
    message = error(result)
    assert "whose profile isn't on here: lidarr." in message
    assert "Set COMPOSE_PROFILES in .env to every profile (COMPOSE_PROFILES=music,requests)" in message
    assert "the backup has no COMPOSE_PROFILES, so it was taken before the profiles" in message
    assert stack.log() == []
