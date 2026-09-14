"""
Copyright (c) 2024, 2025, Oracle and/or its affiliates.
Licensed under the Universal Permissive License v1.0 as shown at http://oss.oracle.com/licenses/upl.
"""

import argparse
import base64
import configparser
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Optional


def base64_encode_file(file_path: Path) -> str:
    """base64 encode the file contents"""
    return base64.b64encode(file_path.read_bytes()).decode()


def extract_key_files(config_text: str) -> list:
    """Extract the contents of the key_file for the secret"""
    key_file_pattern = re.compile(r"key_file\s*=\s*(.+)")
    return [Path(match.strip()).expanduser() for match in key_file_pattern.findall(config_text)]


def rewrite_key_file_paths(config_text: str) -> str:
    """Rewrite key_file paths to target runtime location."""

    def replacer(match):
        original_path = Path(match.group(1).strip())
        new_path = Path("/app/runtime/.oci") / original_path.name
        return f"key_file={new_path}"

    return re.sub(r"key_file\s*=\s*(.+)", replacer, config_text)


def select_profile_config(config_text: str, profile: Optional[str], config_path: Path) -> str:
    """Return config text restricted to the requested profile with DEFAULT fallback."""

    parser = configparser.RawConfigParser(default_section="DEFAULT", dict_type=OrderedDict)
    parser.optionxform = str

    try:
        parser.read_string(config_text)
    except configparser.Error as exc:
        print(f"Error: Failed to parse config file {config_path}: {exc}", file=sys.stderr)
        sys.exit(1)

    defaults = OrderedDict(parser.defaults())
    available_profiles = parser.sections()

    if profile is None:
        if defaults:
            selected_profile = "DEFAULT"
        elif available_profiles:
            selected_profile = available_profiles[0]
        else:
            print(f"Error: No profiles found in config file {config_path}", file=sys.stderr)
            sys.exit(1)
    else:
        selected_profile = profile

    if selected_profile != "DEFAULT" and not parser.has_section(selected_profile):
        available_display = ["DEFAULT"] if defaults else []
        available_display.extend(available_profiles)
        print(
            "Error: Profile "
            f"'{selected_profile}' not found in {config_path}. Available profiles: "
            + ", ".join(available_display),
            file=sys.stderr,
        )
        sys.exit(1)

    merged = OrderedDict(defaults)

    if selected_profile != "DEFAULT":
        section_items = OrderedDict(parser._sections[selected_profile])  # type: ignore[attr-defined]
        merged.update(section_items)

    config_lines = [f"[{selected_profile}]"]
    for key, value in merged.items():
        config_lines.append(f"{key}={value}")
    config_lines.append("")

    return "\n".join(config_lines)


def parse_config_items(config_text: str) -> OrderedDict:
    """Parse a config profile text into ordered key/value pairs."""

    parser = configparser.RawConfigParser(default_section="DEFAULT", dict_type=OrderedDict)
    parser.optionxform = str
    parser.read_string(config_text)

    sections = parser.sections()
    merged_items = OrderedDict(parser.defaults())

    if sections:
        section_name = sections[0]
        merged_items.update(parser._sections[section_name])  # type: ignore[attr-defined]

    return merged_items


def render_secret_yaml(secret_yaml: dict) -> str:
    """Render a secret manifest without PyYAML."""

    metadata = secret_yaml["metadata"]
    data = secret_yaml["data"]

    lines = [
        "apiVersion: v1",
        "kind: Secret",
        "metadata:",
        f"  name: {metadata['name']}",
        f"  namespace: {metadata['namespace']}",
        f"type: {secret_yaml['type']}",
        "data:",
    ]

    for key, value in data.items():
        escaped_value = value.replace('"', '\\"')
        lines.append(f"  {key}: \"{escaped_value}\"")

    lines.append("")
    return "\n".join(lines)


def render_configmap_yaml(configmap_yaml: dict) -> str:
    """Render a configmap manifest without PyYAML."""

    metadata = configmap_yaml["metadata"]
    data = configmap_yaml["data"]

    lines = [
        "apiVersion: v1",
        "kind: ConfigMap",
        "metadata:",
        f"  name: {metadata['name']}",
        f"  namespace: {metadata['namespace']}",
        "data:",
    ]

    for key, value in data.items():
        if "\n" in value:
            lines.append(f"  {key}: |")
            for line in value.splitlines():
                lines.append(f"    {line}")
        else:
            escaped_value = value.replace('"', '\\"')
            lines.append(f"  {key}: \"{escaped_value}\"")

    lines.append("")
    return "\n".join(lines)


def render_manifests(secret_yaml: dict, configmap_yaml: dict) -> str:
    """Return a multi-document YAML string for secret and configmap."""

    secret_str = render_secret_yaml(secret_yaml).rstrip()
    configmap_str = render_configmap_yaml(configmap_yaml).rstrip()
    return "\n---\n".join([secret_str, configmap_str]) + "\n"


def ensure_namespace_exists(namespace: str) -> None:
    """Ensure the Kubernetes namespace exists, creating it if missing."""

    try:
        check_result = subprocess.run(
            ["kubectl", "get", "namespace", namespace],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except FileNotFoundError:
        print("Error: kubectl not found in PATH. Please install kubectl and try again.", file=sys.stderr)
        sys.exit(1)

    if check_result.returncode == 0:
        return

    try:
        create_result = subprocess.run(
            ["kubectl", "create", "namespace", namespace],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        print("Error: kubectl not found in PATH. Please install kubectl and try again.", file=sys.stderr)
        sys.exit(1)

    if create_result.stdout:
        sys.stdout.write(create_result.stdout.decode("utf-8"))
    if create_result.stderr:
        sys.stderr.write(create_result.stderr.decode("utf-8"))

    if create_result.returncode != 0:
        sys.exit(create_result.returncode)


def main():
    """Generate Secret YAML for OCI config file"""

    parser = argparse.ArgumentParser(description="Generate Kubernetes Secret YAML for OCI config")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path.home() / ".oci" / "config",
        help="Path to OCI config file (default: ~/.oci/config)",
    )
    parser.add_argument(
        "--namespace",
        required=True,
        help="Namespace where obaas chart will be deployed",
    )
    parser.add_argument(
        "--profile",
        default=None,
        help="OCI config profile to use (default: DEFAULT profile)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the generated YAML instead of applying it",
    )
    args = parser.parse_args()

    config_path = args.config.expanduser()
    namespace = args.namespace
    profile = args.profile
    dry_run = args.dry_run

    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    # Read original config and extract key files
    original_config_text = config_path.read_text(encoding="utf-8")
    selected_config_text = select_profile_config(original_config_text, profile, config_path)
    key_files = extract_key_files(selected_config_text)
    if not key_files:
        print("Error: No key_file values found in the selected profile", file=sys.stderr)
        sys.exit(1)

    # Check existence of all key files before proceeding
    missing_files = [str(f) for f in key_files if not f.exists()]
    if missing_files:
        print("Error: The following key_file(s) do not exist:", file=sys.stderr)
        for f in missing_files:
            print(f"  - {f}", file=sys.stderr)
        sys.exit(1)

    # Rewrite key_file paths in the config content
    modified_config_text = rewrite_key_file_paths(selected_config_text)
    config_items = parse_config_items(modified_config_text)
    config_items.pop("key_file", None)

    private_key_path = key_files[-1]
    private_key_data = base64_encode_file(private_key_path)

    secret_yaml = {
        "apiVersion": "v1",
        "kind": "Secret",
        "metadata": {"name": "oci-privatekey", "namespace": namespace},
        "type": "Opaque",
        "data": {"privatekey": private_key_data},
    }

    configmap_yaml = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {"name": "oci-config", "namespace": namespace},
        "data": dict(config_items),
    }

    manifests_yaml = render_manifests(secret_yaml, configmap_yaml)

    if dry_run:
        print(manifests_yaml)
        return

    ensure_namespace_exists(namespace)

    try:
        completed = subprocess.run(
            ["kubectl", "apply", "-f", "-"],
            input=manifests_yaml.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except FileNotFoundError:
        print("Error: kubectl not found in PATH. Please install kubectl and try again.")
        sys.exit(1)

    if completed.stdout:
        sys.stdout.write(completed.stdout.decode("utf-8"))
    if completed.stderr:
        sys.stderr.write(completed.stderr.decode("utf-8"))

    if completed.returncode != 0:
        sys.exit(completed.returncode)


if __name__ == "__main__":
    main()
