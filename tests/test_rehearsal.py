"""The steps scripts/rehearse-rebuild.sh takes from docs/rebuilding.md, through its --list mode, and how it runs one,
through its --run-step mode (no Docker).

Each marked block of the doc is a step, in the doc's order, with the doc's host-specific values replaced by the
rehearsal's own; unmarked blocks are never run. A step stops at its first failing command, so a block with `&&` or
`||` (which hide a failure on their left) is refused. Each step runs in a home directory of its own.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).parent.parent
SCRIPT = ROOT / "scripts" / "rehearse-rebuild.sh"
DOC = ROOT / "docs" / "rebuilding.md"
BASH = shutil.which("bash") or "/bin/bash"
MARKER = re.compile(r"^<!-- rehearse: ([a-z0-9-]+) -->\n```sh\n(.*?)^```$", re.MULTILINE | re.DOTALL)


def run_step(tmp_path: Path, commands: str) -> subprocess.CompletedProcess[str]:
    step = tmp_path / "step.sh"
    step.write_text(commands, encoding="utf-8")
    return subprocess.run(  # noqa: S603 # our own script
        [BASH, str(SCRIPT), "--run-step", str(step)],
        capture_output=True,
        text=True,
        check=False,
    )


def listing(doc: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 # our own script
        [BASH, str(SCRIPT), "--list", *([str(doc)] if doc else [])],
        capture_output=True,
        text=True,
        check=False,
    )


def steps(output: str) -> list[tuple[str, str]]:
    """The (name, commands) pairs of a --list output."""
    parts = re.split(r"^--- ([a-z0-9-]+)\n", output, flags=re.MULTILINE)
    return list(zip(parts[1::2], parts[2::2], strict=True))


def minimal_doc(tmp_path: Path, extra: str = "", restore: str = "scripts/restore.sh /path/to/backup") -> Path:
    """A doc with the four required steps, holding every value the rehearsal replaces."""
    doc = tmp_path / "rebuilding.md"
    doc.write_text(
        "# Rebuilding\n\n"
        "<!-- rehearse: decrypt -->\n```sh\n"
        "rsync -rlpt backup-host:/volume1/<folder>/<date>-<time>/ <you>@<the new host>:restore/\n```\n\n"
        "```sh\nsudo apt install -y git   # not marked: never run\n```\n\n"
        "<!-- rehearse: checkout -->\n\n```sh\n"
        "git clone https://github.com/HoneyBearTech/homelab-atlas.git\ncd homelab-atlas\ngit checkout vX.Y.Z\n```\n\n"
        "<!-- rehearse: directories -->\n```sh\nmkdir -p config\n```\n\n"
        f"<!-- rehearse: restore -->\n```sh\n{restore}\n```\n{extra}",
        encoding="utf-8",
    )
    return doc


def test_the_doc_marks_its_steps_in_order() -> None:
    result = listing()
    assert result.returncode == 0, result.stderr
    assert [name for name, _ in steps(result.stdout)] == ["decrypt", "checkout", "directories", "restore"]


def test_each_step_is_its_marked_block_with_only_the_documented_substitutions() -> None:
    marked = MARKER.findall(DOC.read_text(encoding="utf-8"))
    listed = steps(listing().stdout)
    assert [name for name, _ in marked] == [name for name, _ in listed]
    for (_, block), (name, commands) in zip(marked, listed, strict=True):
        # Every line of the block is run; only the host-specific values in it differ.
        assert len(block.splitlines()) == len(commands.splitlines()), name
        for line in block.splitlines():
            if not re.search(r"<[A-Za-z][^>]*>|vX\.Y\.Z|/path/to/backup|github\.com|backup-host:", line):
                assert line in commands.splitlines(), f"{name}: {line}"


def test_no_placeholder_or_real_host_is_left() -> None:
    output = listing().stdout
    assert not re.search(r"<[A-Za-z][A-Za-z ._-]*>", output)
    for value in ("github.com", "backup-host:", "vX.Y.Z", "/path/to/backup"):
        assert value not in output


def test_unmarked_blocks_are_never_run() -> None:
    output = listing().stdout
    for host_only in ("sudo apt", "usermod", "nas.example.internal", "/etc/fstab"):
        assert host_only not in output


def test_a_minimal_doc_runs_its_steps_in_order(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse: check -->\n```sh\ndocker compose ps\n```\n"))
    assert result.returncode == 0, result.stderr
    listed = steps(result.stdout)
    assert [name for name, _ in listed] == ["decrypt", "checkout", "directories", "restore", "check"]
    assert listed[0][1] == "rsync -rlpt $work/backup-server/atlas-backups/YYYYMMDD-HHMMSS/ $work/new-host/restore/\n"
    assert listed[3][1] == "scripts/restore.sh $work/new-host/restore\n"
    assert "sudo apt" not in result.stdout


def test_a_missing_step_fails(tmp_path: Path) -> None:
    doc = minimal_doc(tmp_path)
    doc.write_text(doc.read_text(encoding="utf-8").replace("<!-- rehearse: directories -->\n", ""), encoding="utf-8")
    result = listing(doc)
    assert result.returncode == 1
    assert 'no step "directories"' in result.stderr


def test_a_marker_without_a_block_fails(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse: check -->\nSome text.\n"))
    assert result.returncode == 1
    assert 'step "check" isn\'t followed by a sh fenced block' in result.stderr


def test_two_steps_with_one_name_fail(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse: restore -->\n```sh\ntrue\n```\n"))
    assert result.returncode == 1
    assert 'two steps are named "restore"' in result.stderr


def test_a_malformed_marker_fails(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse:Check -->\n```sh\ntrue\n```\n"))
    assert result.returncode == 1
    assert "unreadable rehearsal marker" in result.stderr


def test_a_block_that_never_ends_fails(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse: check -->\n```sh\ntrue\n"))
    assert result.returncode == 1
    assert "never ends" in result.stderr


def test_a_value_the_doc_no_longer_has_fails(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, restore="scripts/restore.sh ~/restore"))
    assert result.returncode == 1
    assert 'no step in docs/rebuilding.md has "/path/to/backup" any more' in result.stderr


def test_a_placeholder_the_rehearsal_cant_fill_fails(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, restore="scripts/restore.sh /path/to/backup <the service>"))
    assert result.returncode == 1
    assert "placeholder the rehearsal can't fill: <the service>" in result.stderr


def test_and_in_a_marked_block_is_refused(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, restore="scripts/restore.sh /path/to/backup && docker compose ps"))
    assert result.returncode == 1
    assert 'step "restore" has "&&" or "||"' in result.stderr
    assert "put each command on its own line" in result.stderr
    assert "rebuilding.md:" in result.stderr


def test_or_in_a_marked_block_is_refused(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n<!-- rehearse: check -->\n```sh\ndocker compose ps || true\n```\n"))
    assert result.returncode == 1
    assert 'step "check" has "&&" or "||"' in result.stderr


def test_and_or_in_an_unmarked_block_is_left_alone(tmp_path: Path) -> None:
    result = listing(minimal_doc(tmp_path, extra="\n```sh\nsudo apt update && sudo apt full-upgrade -y\n```\n"))
    assert result.returncode == 0, result.stderr


def test_a_failing_first_command_fails_the_step(tmp_path: Path) -> None:
    result = run_step(tmp_path, "false\necho reached\n")
    assert result.returncode != 0
    assert "reached" not in result.stdout


def test_a_settings_file_that_isnt_there_fails_the_step(tmp_path: Path) -> None:
    result = run_step(tmp_path, ". ./.env\nmkdir -p made\necho reached\n")
    assert result.returncode != 0
    assert "reached" not in result.stdout


def test_an_optional_copy_is_skipped_when_the_file_isnt_there(tmp_path: Path) -> None:
    result = run_step(tmp_path, 'if [ -f "$HOME/absent" ]; then cp "$HOME/absent" .; fi\necho reached\n')
    assert result.returncode == 0, result.stderr
    assert result.stdout == "reached\n"


def test_a_step_runs_in_a_home_of_its_own_with_the_callers_docker_settings(tmp_path: Path) -> None:
    result = run_step(tmp_path, 'echo "$HOME"\npwd\necho "$DOCKER_CONFIG"\n')
    assert result.returncode == 0, result.stderr
    home, cwd, docker_config = result.stdout.splitlines()
    assert Path(home).resolve() != Path.home().resolve()
    assert Path(cwd).resolve() == Path(home).resolve()
    assert docker_config == os.environ.get("DOCKER_CONFIG", str(Path.home() / ".docker"))


def test_every_compose_call_outside_the_steps_names_the_hosts_directory() -> None:
    # Otherwise Compose would read a .env in the caller's directory, such as a real installation's.
    for number, line in enumerate(SCRIPT.read_text(encoding="utf-8").splitlines(), start=1):
        if "docker compose" in line and not line.lstrip().startswith("#"):
            assert "--project-directory" in line, f"{SCRIPT.name}:{number}: {line}"
