"""The optional services as Compose profiles: which service is in which profile, and who sees which.

Radarr, Sonarr, Bazarr, SABnzbd and Recyclarr have no profile and always run; every other service is in a profile
that COMPOSE_PROFILES in .env turns on (.env.example turns on all of them). The checks, the image scan, the image
pre-pull and the release SBOM must see the services of every profile, whichever an installation turns on, and
scripts/restore.sh must refuse a backup's service whose profile is off, saying what to do.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parent.parent
FAKE = Path(__file__).parent / "fake_docker.py"
BASH = shutil.which("bash") or "/bin/bash"
CORE = {"radarr", "sonarr", "bazarr", "sabnzbd", "recyclarr"}
PROFILES = {
    "radarr4k": ["4k"],
    "sonarr4k": ["4k"],
    "bazarr4k": ["4k"],
    "lidarr": ["music"],
    "seerr": ["requests"],
    "dozzle": ["logs"],
    "autoheal": ["autoheal"],
    "socket-proxy": ["autoheal"],
}
# Every place that lists the stack's services or images to check, scan, pull or describe them.
CALLERS = (
    ".github/workflows/ci.yml",
    ".github/workflows/scan.yml",
    ".github/workflows/release.yml",
    ".gitlab-ci.yml",
    "Makefile",
)
EVERY_PROFILE = re.compile(r"--profile '\*'|COMPOSE_PROFILES='\*'")


def services() -> dict:
    return yaml.safe_load((ROOT / "compose.yaml").read_text(encoding="utf-8"))["services"]


def test_core_services_have_no_profile() -> None:
    for name in CORE:
        assert "profiles" not in services()[name], f"{name} must always run"


def test_optional_services_carry_their_profile() -> None:
    assert {name: service.get("profiles") for name, service in services().items() if name not in CORE} == PROFILES


def test_env_example_turns_on_every_profile() -> None:
    line = re.search(r"^COMPOSE_PROFILES=(.*)$", (ROOT / ".env.example").read_text(encoding="utf-8"), re.MULTILINE)
    assert line, ".env.example doesn't set COMPOSE_PROFILES"
    every = {profile for service in services().values() for profile in service.get("profiles") or []}
    assert set(line.group(1).split(",")) == every


def test_every_dependency_runs_whenever_its_dependent_does() -> None:
    stack = services()
    for name, service in stack.items():
        mine = set(service.get("profiles") or [])
        for dependency in service.get("depends_on") or []:
            theirs = set(stack[dependency].get("profiles") or [])
            assert not theirs or (mine and mine <= theirs), (
                f"{name} depends on {dependency}, which doesn't run whenever {name} does"
            )


@pytest.mark.parametrize("path", CALLERS)
def test_every_service_list_covers_every_profile(path: str) -> None:
    text = (ROOT / path).read_text(encoding="utf-8")
    calls = [
        line
        for line in text.splitlines()
        if re.search(r"docker compose\b.*\bconfig\b", line) and not line.lstrip().startswith("#")
    ]
    if path == "Makefile":
        # `make config` prints the file as this installation runs it; `make check` checks every profile.
        calls = [line for line in calls if "check_compose.py" in line]
    assert calls, f"{path} no longer runs docker compose config"
    for line in calls:
        assert EVERY_PROFILE.search(line), f"{path} misses the services of a profile that is off: {line.strip()}"


def test_restore_refuses_a_service_whose_profile_is_off(tmp_path: Path) -> None:
    state = tmp_path / "state.json"
    stack = {"services": {"radarr": {"state": "running"}, "seerr": {"state": "running"}}, "inactive": ["seerr"]}
    state.write_text(json.dumps({**stack, "fail_stop": {}, "fail_start": [], "log": []}), encoding="utf-8")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    docker = bin_dir / "docker"
    docker.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKE}" "$@"\n', encoding="utf-8")
    docker.chmod(0o755)

    backup = tmp_path / "backup"
    (backup / "env").mkdir(parents=True)
    (backup / "env" / ".env").write_text("COMPOSE_PROFILES=requests\n", encoding="utf-8")
    manifest = "# archive\tservice\tmount\tsource\timage\n"
    for service in stack["services"]:
        (backup / f"{service}--config.tar.gz").write_bytes(b"an archive")
        manifest += f"{service}--config.tar.gz\t{service}\t/config\t/srv/{service}/config\texample/{service}:1\n"
    (backup / "MANIFEST").write_text(manifest, encoding="utf-8")
    sums = "".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(backup)}\n"
        for path in sorted(backup.rglob("*"))
        if path.is_file()
    )
    (backup / "SHA256SUMS").write_text(sums, encoding="utf-8")

    env = {
        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
        "HOME": "/nonexistent",
        "FAKE_DOCKER_STATE": str(state),
        "HOMELAB_PULL_STATE_DIR": str(tmp_path / "homelab-pull"),
    }
    # S603: fixed argv, no shell.
    result = subprocess.run(  # noqa: S603
        [BASH, str(ROOT / "scripts" / "restore.sh"), "--yes", str(backup)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 1, result.stderr
    error = " ".join(result.stderr.split())
    assert "whose profile isn't on here: seerr." in error
    assert "Set COMPOSE_PROFILES in .env as when the backup was taken (COMPOSE_PROFILES=requests" in error
    assert "Nothing changed." in error
    assert json.loads(state.read_text(encoding="utf-8"))["log"] == [], "restore.sh stopped or started a service"
