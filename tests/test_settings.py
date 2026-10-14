import re
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
APPS = ("radarr", "radarr4k", "sonarr", "sonarr4k", "lidarr", "bazarr", "bazarr4k", "sabnzbd")


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
        assert "${CONFIG_ROOT:?set CONFIG_ROOT in .env}/" + app + "/config:/config" in services[app]["volumes"]


def test_no_named_volumes() -> None:
    config = compose()
    assert "volumes" not in config
    for name, service in config["services"].items():
        for volume in service.get("volumes") or []:
            assert volume.startswith(("/", "${")), f"{name} mounts a named volume: {volume}"
