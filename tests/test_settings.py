import re
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
APPS = ("radarr", "radarr4k", "sonarr", "sonarr4k", "lidarr", "bazarr", "bazarr4k", "sabnzbd", "recyclarr")
CONFIG_ROOT = "${CONFIG_ROOT:?set CONFIG_ROOT in .env}"
# Host sources that aren't an app's own data: the media and download roots, and the Docker socket (policy exceptions).
SHARED = ("${MEDIA_ROOT:?set MEDIA_ROOT in .env}:", "${SABNZBD_INCOMPLETE_PATH:?set SABNZBD_INCOMPLETE_PATH in .env}:")
SOCKET = "/var/run/docker.sock:/var/run/docker.sock:ro"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def compose() -> dict:
    return yaml.safe_load(read("compose.yaml"))


def test_every_setting_is_in_env_example_and_interfaces() -> None:
    used = set(re.findall(r"\$\{([A-Z][A-Z0-9_]*)", read("compose.yaml")))
    example = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", read(".env.example"), re.MULTILINE))
    table = re.findall(r"^\| (`[A-Z][^|]*) \|", read("docs/interfaces.md"), re.MULTILINE)
    documented = {name for cell in table for name in re.findall(r"`([A-Z][A-Z0-9_]*)`", cell)}
    assert used == example
    assert used <= documented


def test_each_app_keeps_its_config_in_a_directory_under_config_root() -> None:
    services = compose()["services"]
    for app in APPS:
        assert f"{CONFIG_ROOT}/{app}/config:/config" in services[app]["volumes"]


def test_every_app_data_mount_is_a_folder_of_its_own_under_config_root() -> None:
    for name, service in compose()["services"].items():
        for volume in service.get("volumes") or []:
            if volume == SOCKET or volume.startswith(SHARED):
                continue
            source = volume.split(":/", 1)[0]
            assert re.fullmatch(re.escape(f"{CONFIG_ROOT}/{name}/") + r"[a-z0-9-]+", source), (
                f"{name} mounts {volume}: app data belongs in CONFIG_ROOT/{name}/<purpose>"
            )


def test_no_setting_points_into_dockers_own_directories() -> None:
    for path in (".env.example", "compose.yaml"):
        assert "/var/lib/docker/" not in "".join(
            line for line in read(path).splitlines(keepends=True) if not line.lstrip().startswith("#")
        ), f"{path} points into /var/lib/docker"


def test_the_docs_warn_against_docker_volumes() -> None:
    for path in ("docs/installing.md", "CLAUDE.md", ".env.example"):
        text = " ".join(read(path).split())
        assert "/var/lib/docker/volumes" in text, path
        assert "docker volume prune" in text, path


def test_no_named_volumes() -> None:
    config = compose()
    assert "volumes" not in config
    for name, service in config["services"].items():
        for volume in service.get("volumes") or []:
            assert volume.startswith(("/", "${")), f"{name} mounts a named volume: {volume}"
