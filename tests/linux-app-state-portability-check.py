"""Portable smoke coverage for the Linux guest app-state placeholder module."""

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace


module_path = Path(sys.argv[1])
source_home = str(Path(tempfile.gettempdir()) / "prodicloud-source-profile")
target_home = str(Path(tempfile.gettempdir()) / "prodicloud-target-profile")


def fake_getpwnam(user_name: str):
    home = source_home if user_name == "source-user" else target_home
    uid = 1001 if user_name == "source-user" else 2002
    return SimpleNamespace(pw_name=user_name, pw_dir=home, pw_uid=uid, pw_gid=uid)


sys.modules["pwd"] = SimpleNamespace(getpwnam=fake_getpwnam)
spec = importlib.util.spec_from_file_location("prodicloud_app_state_portability", module_path)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
sys.modules[spec.name] = module
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="prodicloud-linux-app-state-") as temp_root:
    payload = Path(temp_root) / "payload" / "profile-files" / "manager"
    payload.mkdir(parents=True)
    settings_path = payload / "settings.json"
    manifest_path = Path(temp_root) / "app-state.manifest.json"
    original = {
        "workspace": source_home + "/Documents",
        "hostname": "source-machine",
        "api_key": "must-be-removed",
        "cpu_count": "%PRODICLOUD_TARGET_CPU_COUNT%",
    }
    settings_path.write_text(json.dumps(original), encoding="utf-8")
    manifest = {
        "version": 3,
        "taskName": "linux-portability-fixture",
        "machineDirectories": [],
        "machineFiles": [],
        "profileDirectories": [],
        "profileFiles": [
            {
                "sourcePath": "payload/profile-files/manager/settings.json",
                "relativeDestinationPath": "%PRODICLOUD_TARGET_HOME%/Documents/settings.json",
                "targetProfiles": ["manager"],
            }
        ],
        "registryImports": [],
    }
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    saved_manifest = module.normalize_captured_payload(temp_root, manifest, "source-user", "")
    saved_settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert saved_settings["workspace"] == "%PRODICLOUD_TARGET_HOME%/Documents"
    assert "api_key" not in saved_settings
    assert saved_manifest["profileFiles"][0]["sourcePath"] == "payload/profile-files/manager/settings.json"

    replay_manifest, targets = module.prepare_payload_for_restore(temp_root, saved_manifest, "target-user", "")
    replay_settings = json.loads(settings_path.read_text(encoding="utf-8"))
    assert targets == [("manager", "target-user", target_home)]
    assert replay_manifest["profileFiles"][0]["relativeDestinationPath"] == target_home + "/Documents/settings.json"
    assert replay_settings["workspace"] == target_home + "/Documents"
    assert replay_settings["hostname"] != "source-machine"
    assert replay_settings["cpu_count"] == str(os.cpu_count() or "")

print("[PASS] Linux app-state capture and target replay generalization")
