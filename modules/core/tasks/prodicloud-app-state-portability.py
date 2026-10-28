"""Portable placeholder processing for Linux guest app-state payloads."""

from __future__ import annotations

import copy
import json
import os
import platform
import pwd
import re
import socket
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any


TOKEN_PATTERN = re.compile(r"%PRODICLOUD_[A-Z0-9_]+%")
SENSITIVE_KEY_PATTERN = re.compile(
    r"password|secret|token|credential|(?:^|[._-])auth|api.?key|private.?key|"
    r"account|email|gaia|sign.?in|sync|client.?id|machine.?id|device.?id|"
    r"subscription|tenant|refresh.?token|access.?token",
    re.IGNORECASE,
)
PROFILE_DATA_KEY_PATTERN = re.compile(r"^(?:uid|user.?id|gid|group.?id)$", re.IGNORECASE)
HOST_DATA_KEY_PATTERN = re.compile(r"^(?:hostname|computername|host.?name)$", re.IGNORECASE)
TEXT_EXTENSIONS = {
    ".cfg", ".conf", ".desktop", ".ini", ".json", ".properties", ".service",
    ".sh", ".toml", ".txt", ".xml", ".yaml", ".yml",
}


def _profile_for_user(user_name: str, label: str) -> dict[str, Any] | None:
    if not user_name:
        return None
    try:
        entry = pwd.getpwnam(user_name)
        home = os.path.normpath(entry.pw_dir)
        return {"label": label, "user": entry.pw_name, "home": home, "uid": entry.pw_uid, "gid": entry.pw_gid}
    except (KeyError, OSError):
        fallback = os.path.normpath(os.path.join("/home", user_name))
        if not os.path.isdir(fallback):
            return None
        return {"label": label, "user": user_name, "home": fallback, "uid": "", "gid": ""}


def _first_ipv4() -> str:
    try:
        candidates = socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
    except OSError:
        return ""
    for candidate in candidates:
        address = str(candidate[4][0])
        if address and not address.startswith(("127.", "169.254.")):
            return address
    return ""


def _memory_gib() -> str:
    try:
        pages = int(os.sysconf("SC_PHYS_PAGES"))
        page_size = int(os.sysconf("SC_PAGE_SIZE"))
        if pages > 0 and page_size > 0:
            return f"{(pages * page_size) / (1024 ** 3):.2f}".rstrip("0").rstrip(".")
    except (AttributeError, OSError, TypeError, ValueError):
        pass
    return ""


def build_context(manager_user: str, assistant_user: str) -> tuple[dict[str, dict[str, Any]], dict[str, str]]:
    profiles: dict[str, dict[str, Any]] = {}
    for label, user_name in (("manager", manager_user), ("assistant", assistant_user)):
        target = _profile_for_user(str(user_name or ""), label)
        if target:
            profiles[label] = target

    machine = {
        "PRODICLOUD_COMPUTER_NAME": platform.node() or socket.gethostname(),
        "PRODICLOUD_PRIMARY_IPV4_ADDRESS": _first_ipv4(),
        "PRODICLOUD_TARGET_CPU_COUNT": str(os.cpu_count() or ""),
        "PRODICLOUD_TARGET_MEMORY_GB": _memory_gib(),
        "PRODICLOUD_SYSTEM_ROOT": os.path.sep,
        "PRODICLOUD_PROGRAM_DATA": "/var/lib",
        "PRODICLOUD_PROGRAM_FILES": "/usr/local/bin",
        "PRODICLOUD_PROGRAM_FILES_X86": "/usr/lib",
    }
    return profiles, machine


def _profile_values(profile: dict[str, Any], profiles: dict[str, dict[str, Any]], machine: dict[str, str]) -> dict[str, str]:
    label = str(profile.get("label", ""))
    home = str(profile.get("home", ""))
    values = dict(machine)
    values.update(
        {
            "PRODICLOUD_TARGET_USER": str(profile.get("user", "")),
            "PRODICLOUD_TARGET_PROFILE_PATH": home,
            "PRODICLOUD_TARGET_HOME": home,
            "PRODICLOUD_TARGET_UID": str(profile.get("uid", "")),
            "PRODICLOUD_TARGET_GID": str(profile.get("gid", "")),
            "PRODICLOUD_LOCAL_APP_DATA": os.path.join(home, ".local", "share"),
            "PRODICLOUD_ROAMING_APP_DATA": os.path.join(home, ".config"),
            "PRODICLOUD_VM_ADMIN_USER": str(profiles.get("manager", {}).get("user", "")),
            "PRODICLOUD_ASSISTANT_USER": str(profiles.get("assistant", {}).get("user", "")),
            "PRODICLOUD_VM_ADMIN_HOME": str(profiles.get("manager", {}).get("home", "")),
            "PRODICLOUD_ASSISTANT_HOME": str(profiles.get("assistant", {}).get("home", "")),
            "PRODICLOUD_VM_ADMIN_PROFILE_PATH": str(profiles.get("manager", {}).get("home", "")),
            "PRODICLOUD_ASSISTANT_PROFILE_PATH": str(profiles.get("assistant", {}).get("home", "")),
            "PRODICLOUD_VM_ADMIN_UID": str(profiles.get("manager", {}).get("uid", "")),
            "PRODICLOUD_ASSISTANT_UID": str(profiles.get("assistant", {}).get("uid", "")),
            "PRODICLOUD_VM_ADMIN_GID": str(profiles.get("manager", {}).get("gid", "")),
            "PRODICLOUD_ASSISTANT_GID": str(profiles.get("assistant", {}).get("gid", "")),
        }
    )
    if label not in profiles:
        raise RuntimeError(f"App-state profile label is not available on the target: {label}")
    return values


def _replace_tokens(value: str, replacements: dict[str, str], source_name: str) -> str:
    result = str(value)
    for name, replacement in replacements.items():
        result = result.replace(f"%{name}%", str(replacement))
    unresolved = TOKEN_PATTERN.findall(result)
    if unresolved:
        raise RuntimeError(f"Unsupported or unavailable app-state placeholder {unresolved[0]} in {source_name}.")
    return result


def _actual_path_tokens(profile: dict[str, Any], profiles: dict[str, dict[str, Any]]) -> dict[str, str]:
    result: dict[str, str] = {}
    for label, item in profiles.items():
        home = str(item.get("home", ""))
        if not home:
            continue
        token = "PRODICLOUD_TARGET_HOME" if label == str(profile.get("label", "")) else ("PRODICLOUD_VM_ADMIN_HOME" if label == "manager" else "PRODICLOUD_ASSISTANT_HOME")
        result[home] = f"%{token}%"
    return result


def _normalize_string(value: str, profile: dict[str, Any] | None, profiles: dict[str, dict[str, Any]], machine: dict[str, str]) -> str:
    result = str(value)
    actual_paths = _actual_path_tokens(profile or {}, profiles)
    for path in sorted(actual_paths, key=len, reverse=True):
        result = result.replace(path, actual_paths[path])
    source_host = str(machine.get("PRODICLOUD_COMPUTER_NAME", ""))
    if source_host:
        result = re.sub(rf"(?<![A-Za-z0-9_.-]){re.escape(source_host)}(?![A-Za-z0-9_.-])", "%PRODICLOUD_COMPUTER_NAME%", result, flags=re.IGNORECASE)
    source_ip = str(machine.get("PRODICLOUD_PRIMARY_IPV4_ADDRESS", ""))
    if source_ip:
        result = re.sub(rf"(?<![0-9.]){re.escape(source_ip)}(?![0-9.])", "%PRODICLOUD_PRIMARY_IPV4_ADDRESS%", result)
    return result


def _portable_value(value: Any, profile: dict[str, Any] | None, profiles: dict[str, dict[str, Any]], machine: dict[str, str], source_name: str) -> Any:
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        replacements = _profile_values(profile, profiles, machine) if profile else machine
        for raw_key, item in value.items():
            key = str(raw_key)
            if SENSITIVE_KEY_PATTERN.search(key):
                continue
            if PROFILE_DATA_KEY_PATTERN.fullmatch(key):
                token_name = "PRODICLOUD_TARGET_UID" if key.lower() in {"uid", "user_id"} else "PRODICLOUD_TARGET_GID"
                result[key] = f"%{token_name}%"
                continue
            if HOST_DATA_KEY_PATTERN.fullmatch(key):
                result[key] = "%PRODICLOUD_COMPUTER_NAME%"
                continue
            result[key] = _portable_value(item, profile, profiles, machine, source_name)
        return result
    if isinstance(value, list):
        return [_portable_value(item, profile, profiles, machine, source_name) for item in value]
    if isinstance(value, str):
        return _normalize_string(value, profile, profiles, machine)
    return value


def _strip_sensitive_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _strip_sensitive_value(item) for key, item in value.items() if not SENSITIVE_KEY_PATTERN.search(str(key))}
    if isinstance(value, list):
        return [_strip_sensitive_value(item) for item in value]
    return value


def _owner_label(relative_path: str) -> str:
    parts = Path(relative_path).parts
    if len(parts) > 2 and parts[0] == "payload" and parts[1] in {"profile-directories", "profile-files"} and parts[2] in {"manager", "assistant"}:
        return str(parts[2])
    if len(parts) > 3 and parts[:2] == ("payload", "registry") and parts[2] == "user" and parts[3] in {"manager", "assistant"}:
        return str(parts[3])
    return ""


def _sanitize_text(content: str) -> str:
    lines = []
    skip_sensitive_section = False
    for line in str(content).splitlines():
        section = re.match(r"^\s*\[([^\]]+)\]\s*$", line)
        if section:
            skip_sensitive_section = bool(SENSITIVE_KEY_PATTERN.search(section.group(1)))
            if skip_sensitive_section:
                continue
        if skip_sensitive_section:
            continue
        if line.lstrip().startswith(("#", ";")):
            lines.append(line)
            continue
        key = re.match(r"^\s*[\"']?([A-Za-z0-9_.-]+)[\"']?\s*(?:=|:)", line)
        if key and SENSITIVE_KEY_PATTERN.search(key.group(1)):
            continue
        if re.search(r"(?:gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})", line):
            continue
        lines.append(line)
    return "\n".join(lines) + ("\n" if str(content).endswith("\n") else "")


def _sanitize_xml(content: str) -> str:
    try:
        root = ET.fromstring(content)
    except ET.ParseError:
        return _sanitize_text(content)
    for parent in root.iter():
        for child in list(parent):
            if SENSITIVE_KEY_PATTERN.search(child.tag.split("}")[-1]):
                parent.remove(child)
                continue
            for attribute in list(child.attrib):
                if SENSITIVE_KEY_PATTERN.search(attribute):
                    del child.attrib[attribute]
    return ET.tostring(root, encoding="unicode")


def _profile_scoped(collection: str, entry: dict[str, Any]) -> bool:
    return collection in {"profileDirectories", "profileFiles"} or (collection == "registryImports" and str(entry.get("scope", "")).lower() == "user")


def resolve_manifest(manifest: dict[str, Any], profiles: dict[str, dict[str, Any]], machine: dict[str, str]) -> dict[str, Any]:
    for collection in ("machineDirectories", "machineFiles", "profileDirectories", "profileFiles", "registryImports"):
        resolved_entries = []
        for entry in manifest.get(collection, []):
            is_profile = _profile_scoped(collection, entry)
            labels = [str(label).strip().lower() for label in entry.get("targetProfiles", []) if str(label).strip()]
            if is_profile:
                labels = [label for label in labels if label in profiles] or list(profiles.keys())
            else:
                labels = [""]
            for label in labels:
                copy_entry = copy.deepcopy(entry)
                context = _profile_values(profiles[label], profiles, machine) if label else machine
                copy_entry = _expand_value(copy_entry, context, f"manifest.{collection}")
                if is_profile:
                    copy_entry["targetProfiles"] = [label]
                resolved_entries.append(copy_entry)
        manifest[collection] = resolved_entries
    return manifest


def _expand_value(value: Any, replacements: dict[str, str], source_name: str) -> Any:
    if isinstance(value, dict):
        return {key: _expand_value(item, replacements, source_name) for key, item in value.items()}
    if isinstance(value, list):
        return [_expand_value(item, replacements, source_name) for item in value]
    if isinstance(value, str):
        return _replace_tokens(value, replacements, source_name)
    return value


def normalize_captured_payload(scratch_root: str, manifest: dict[str, Any], manager_user: str, assistant_user: str) -> dict[str, Any]:
    profiles, machine = build_context(manager_user, assistant_user)

    for collection in ("machineDirectories", "machineFiles", "profileDirectories", "profileFiles", "registryImports"):
        for entry in manifest.get(collection, []):
            labels = [str(label).lower() for label in entry.get("targetProfiles", []) if str(label).lower() in profiles]
            profile = profiles.get(labels[0]) if len(labels) == 1 else None
            replacements = _profile_values(profile, profiles, machine) if profile else machine
            for key, value in list(entry.items()):
                if isinstance(value, str):
                    entry[key] = _normalize_string(value, profile, profiles, machine)

    payload_root = os.path.join(scratch_root, "payload")
    for current_root, _, file_names in os.walk(payload_root):
        for file_name in file_names:
            path = os.path.join(current_root, file_name)
            relative = os.path.relpath(path, scratch_root)
            extension = Path(file_name).suffix.lower()
            if extension not in TEXT_EXTENSIONS and file_name != "config":
                continue
            try:
                content = Path(path).read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            if "\x00" in content:
                continue
            label = _owner_label(relative)
            profile = profiles.get(label)
            if extension == ".json":
                try:
                    value = _strip_sensitive_value(json.loads(content))
                except json.JSONDecodeError:
                    content = _sanitize_text(content)
                else:
                    content = json.dumps(_portable_value(value, profile, profiles, machine, relative), indent=2, ensure_ascii=False) + "\n"
            elif extension == ".xml":
                content = _sanitize_xml(content)
            else:
                content = _sanitize_text(content)
            actual_paths = _actual_path_tokens(profile or {}, profiles)
            for actual_path in sorted(actual_paths, key=len, reverse=True):
                content = content.replace(actual_path, actual_paths[actual_path])
            host = str(machine.get("PRODICLOUD_COMPUTER_NAME", ""))
            if host:
                content = re.sub(rf"(?<![A-Za-z0-9_.-]){re.escape(host)}(?![A-Za-z0-9_.-])", "%PRODICLOUD_COMPUTER_NAME%", content, flags=re.IGNORECASE)
            address = str(machine.get("PRODICLOUD_PRIMARY_IPV4_ADDRESS", ""))
            if address:
                content = re.sub(rf"(?<![0-9.]){re.escape(address)}(?![0-9.])", "%PRODICLOUD_PRIMARY_IPV4_ADDRESS%", content)
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(content)
    return manifest


def prepare_payload_for_restore(scratch_root: str, manifest: dict[str, Any], manager_user: str, assistant_user: str) -> tuple[dict[str, Any], list[tuple[str, str, str]]]:
    profiles, machine = build_context(manager_user, assistant_user)
    profile_targets = [(label, str(item["user"]), str(item["home"])) for label, item in profiles.items()]
    manifest = resolve_manifest(manifest, profiles, machine)

    for current_root, _, file_names in os.walk(os.path.join(scratch_root, "payload")):
        for file_name in file_names:
            path = os.path.join(current_root, file_name)
            relative = os.path.relpath(path, scratch_root)
            extension = Path(file_name).suffix.lower()
            if extension not in TEXT_EXTENSIONS and file_name != "config":
                continue
            try:
                content = Path(path).read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            if "\x00" in content:
                continue
            label = _owner_label(relative)
            context = _profile_values(profiles[label], profiles, machine) if label in profiles else machine
            if extension == ".json":
                try:
                    value = json.loads(content)
                except json.JSONDecodeError:
                    content = _expand_value(_sanitize_text(content), context, relative)
                else:
                    content = json.dumps(_expand_value(value, context, relative), indent=2, ensure_ascii=False) + "\n"
            else:
                safe_content = _sanitize_xml(content) if extension == ".xml" else _sanitize_text(content)
                content = _expand_value(safe_content, context, relative)
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(content)
    return manifest, profile_targets
