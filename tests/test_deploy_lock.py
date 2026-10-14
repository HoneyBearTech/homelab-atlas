"""deploy_lock in scripts/lib.sh: backup.sh and restore.sh wait for the pull agent's deploys and hold its lock.

Each test runs bash, sources lib.sh and calls deploy_lock with the agent's state directory in a temporary directory.
A Python fcntl.flock on the same lock file stands in for the agent (flock(1) uses the same flock(2) lock).
"""

from __future__ import annotations

import fcntl
import os
import re
import shutil
import subprocess
import threading
from contextlib import contextmanager, suppress
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

if TYPE_CHECKING:
    from collections.abc import Iterator

ROOT = Path(__file__).parent.parent
LIB = ROOT / "scripts" / "lib.sh"
BASH = shutil.which("bash") or "/bin/bash"
STACK = "atlas"
needs_flock = pytest.mark.skipif(
    shutil.which("flock") is None, reason="flock isn't installed (util-linux; macOS has none)"
)


def env(**settings: str) -> dict[str, str]:
    """A minimal environment: PATH, a HOME with nothing in it unless given, and the given settings."""
    return {"PATH": os.environ["PATH"], "HOME": "/nonexistent", **settings}


def command(script: str) -> list[str]:
    """bash running `script` after sourcing lib.sh, with -eu so a failed deploy_lock stops it."""
    return [BASH, "-euc", f'. "$1"\n{script}', "bash", str(LIB)]


def run(script: str, settings: dict[str, str]) -> subprocess.CompletedProcess[str]:
    # S603: fixed argv, no shell; the script text is the test's own.
    return subprocess.run(command(script), env=settings, capture_output=True, text=True, check=False, timeout=60)  # noqa: S603


def stack_dir(state: Path) -> Path:
    path = state / STACK
    path.mkdir(parents=True)
    return path


@contextmanager
def deploy(lock: Path) -> Iterator[int]:
    """A stand-in deploy by the agent: holds the lock until the block ends (or the returned fd is closed)."""
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    try:
        yield fd
    finally:
        with suppress(OSError):
            os.close(fd)


def is_locked(lock: Path) -> bool:
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return True
    finally:
        os.close(fd)
    return False


def test_lib_names_this_stack() -> None:
    assert run('printf %s "$pull_stack"', env()).stdout == STACK


@pytest.mark.parametrize("variable", ["HOMELAB_PULL_STATE_DIR", "XDG_STATE_HOME"])
def test_no_state_directory_does_nothing_and_creates_nothing(tmp_path: Path, variable: str) -> None:
    before = sorted(tmp_path.rglob("*"))
    out = run("deploy_lock\necho ran", env(**{variable: str(tmp_path)}))
    assert (out.returncode, out.stdout, out.stderr) == (0, "ran\n", "")
    assert sorted(tmp_path.rglob("*")) == before


def test_no_default_state_directory_does_nothing(tmp_path: Path) -> None:
    out = run("deploy_lock\necho ran", env(HOME=str(tmp_path)))
    assert (out.returncode, out.stdout, out.stderr) == (0, "ran\n", "")
    assert list(tmp_path.iterdir()) == []


def test_state_directory_without_flock_fails(tmp_path: Path) -> None:
    stack_dir(tmp_path)
    out = run("deploy_lock\necho ran", env(HOMELAB_PULL_STATE_DIR=str(tmp_path), PATH=str(tmp_path / "bin")))
    assert out.returncode == 1
    assert out.stdout == ""
    assert "flock isn't installed" in out.stderr


@needs_flock
@pytest.mark.parametrize("variable", ["HOMELAB_PULL_STATE_DIR", "XDG_STATE_HOME"])
def test_lock_is_held_until_the_script_exits(tmp_path: Path, variable: str) -> None:
    state = tmp_path if variable == "HOMELAB_PULL_STATE_DIR" else tmp_path / "homelab-pull"
    lock = stack_dir(state) / "lock"
    # S603: fixed argv, no shell. The script holds the lock, says so, then waits for a line on stdin.
    with subprocess.Popen(  # noqa: S603
        command("deploy_lock\necho locked\nread -r _"),
        env=env(**{variable: str(tmp_path)}),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    ) as script:
        assert script.stdin is not None
        assert script.stdout is not None
        try:
            assert script.stdout.readline() == "locked\n"
            assert is_locked(lock)
            script.stdin.write("\n")
            script.stdin.close()
            assert script.wait(timeout=30) == 0
        finally:
            script.kill()
    assert not is_locked(lock)


@needs_flock
def test_waits_for_a_running_deploy(tmp_path: Path) -> None:
    lock = stack_dir(tmp_path) / "lock"
    with deploy(lock) as fd:
        finish = threading.Timer(1.0, os.close, [fd])
        finish.start()
        out = run("deploy_lock_timeout=30\ndeploy_lock\necho ran", env(HOMELAB_PULL_STATE_DIR=str(tmp_path)))
        finish.join()
    assert out.returncode == 0, out.stderr
    assert out.stdout == "Waiting for a deploy by the pull agent to finish (up to 30 s)\nran\n"


@needs_flock
def test_times_out_with_a_clear_error_and_runs_nothing_after(tmp_path: Path) -> None:
    lock = stack_dir(tmp_path) / "lock"
    with deploy(lock):
        out = run("deploy_lock_timeout=1\ndeploy_lock\necho ran", env(HOMELAB_PULL_STATE_DIR=str(tmp_path)))
    assert out.returncode == 1
    assert out.stdout == "Waiting for a deploy by the pull agent to finish (up to 1 s)\n"
    assert f"still holds {lock} after 1 s" in out.stderr
    assert f"homelab-pull@{STACK}" in out.stderr


@pytest.mark.parametrize("script", ["backup.sh", "restore.sh"])
def test_scripts_lock_right_after_entering_the_checkout(script: str) -> None:
    code = [
        line.strip()
        for line in (ROOT / "scripts" / script).read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    entered = code.index('cd "$root"')
    assert code[entered + 1] == "deploy_lock"
    assert code[entered - 1] == '. "$root/scripts/lib.sh"'
    # Nothing touches Docker (stops, creates or recreates a container) before the lock.
    assert not any(re.search(r"\bdocker\b", line) for line in code[:entered])
