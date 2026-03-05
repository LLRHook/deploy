#!/usr/bin/env python3
"""
Manage .deploy.json configuration files.

Usage:
    python deploy_config.py init <repo_path> --architecture <arch>
    python deploy_config.py read <repo_path>
    python deploy_config.py update <repo_path> --key <dotted.key> --value <value>
    python deploy_config.py validate <repo_path>
"""

import json
import sys
import os
from datetime import datetime, timezone
from pathlib import Path


SCHEMA_VERSION = "1.0"

TEMPLATE = {
    "version": SCHEMA_VERSION,
    "createdAt": None,
    "lastDeployed": None,
    "architecture": None,
    "vercel": {
        "projectId": None,
        "projectName": None,
        "teamId": None,
        "deploymentUrl": None,
        "customDomain": None,
        "stripeIntegrated": False,
        "envVars": []
    },
    "railway": {
        "projectId": None,
        "environmentId": None,
        "services": {
            "postgres": {
                "serviceId": None,
                "connectionVar": "DATABASE_URL"
            },
            "redis": {
                "serviceId": None,
                "connectionVar": "REDIS_URL"
            },
            "backend": {
                "serviceId": None,
                "url": None,
                "customDomain": None
            }
        }
    },
    "stripe": {
        "mode": "test",
        "webhookConfigured": False
    }
}


def config_path(repo_path: str) -> Path:
    return Path(repo_path) / ".deploy.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def init_config(repo_path: str, architecture: str) -> dict:
    """Create a new .deploy.json with default values."""
    cfg = json.loads(json.dumps(TEMPLATE))  # deep copy
    cfg["createdAt"] = now_iso()
    cfg["architecture"] = architecture

    path = config_path(repo_path)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)

    print(f"Created {path}")
    return cfg


def read_config(repo_path: str) -> dict:
    """Read existing .deploy.json."""
    path = config_path(repo_path)
    if not path.exists():
        print(f"No .deploy.json found at {path}", file=sys.stderr)
        sys.exit(1)

    with open(path) as f:
        cfg = json.load(f)

    return cfg


def update_config(repo_path: str, key: str, value: str) -> dict:
    """Update a dotted key in .deploy.json (e.g., 'vercel.projectId')."""
    cfg = read_config(repo_path)

    keys = key.split(".")
    obj = cfg
    for k in keys[:-1]:
        if k not in obj:
            obj[k] = {}
        obj = obj[k]

    # Try to parse value as JSON (for booleans, arrays, etc.)
    try:
        parsed = json.loads(value)
        obj[keys[-1]] = parsed
    except (json.JSONDecodeError, TypeError):
        obj[keys[-1]] = value

    cfg["lastDeployed"] = now_iso()

    path = config_path(repo_path)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)

    print(f"Updated {key} = {value}")
    return cfg


def validate_config(repo_path: str) -> bool:
    """Validate that .deploy.json has the minimum required fields populated."""
    cfg = read_config(repo_path)

    issues = []

    if not cfg.get("architecture"):
        issues.append("Missing: architecture")

    if not cfg.get("vercel", {}).get("projectId"):
        issues.append("Missing: vercel.projectId")

    if not cfg.get("railway", {}).get("projectId"):
        issues.append("Missing: railway.projectId")

    if not cfg.get("railway", {}).get("environmentId"):
        issues.append("Missing: railway.environmentId")

    # Check if at least postgres is provisioned
    pg = cfg.get("railway", {}).get("services", {}).get("postgres", {})
    if not pg.get("serviceId"):
        issues.append("Missing: railway.services.postgres.serviceId")

    if not cfg.get("vercel", {}).get("deploymentUrl"):
        issues.append("Missing: vercel.deploymentUrl (not yet deployed?)")

    if issues:
        print("Validation issues:")
        for issue in issues:
            print(f"  - {issue}")
        return False
    else:
        print("Config is valid. All required fields populated.")
        return True


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]

    if command == "init":
        repo = sys.argv[2] if len(sys.argv) > 2 else "."
        arch = None
        for i, arg in enumerate(sys.argv):
            if arg == "--architecture" and i + 1 < len(sys.argv):
                arch = sys.argv[i + 1]
        if not arch:
            print("Error: --architecture required (nextjs-fullstack or separate-frontend-backend)")
            sys.exit(1)
        cfg = init_config(repo, arch)
        print(json.dumps(cfg, indent=2))

    elif command == "read":
        repo = sys.argv[2] if len(sys.argv) > 2 else "."
        cfg = read_config(repo)
        print(json.dumps(cfg, indent=2))

    elif command == "update":
        repo = sys.argv[2] if len(sys.argv) > 2 else "."
        key = value = None
        for i, arg in enumerate(sys.argv):
            if arg == "--key" and i + 1 < len(sys.argv):
                key = sys.argv[i + 1]
            if arg == "--value" and i + 1 < len(sys.argv):
                value = sys.argv[i + 1]
        if not key or value is None:
            print("Error: --key and --value required")
            sys.exit(1)
        cfg = update_config(repo, key, value)
        print(json.dumps(cfg, indent=2))

    elif command == "validate":
        repo = sys.argv[2] if len(sys.argv) > 2 else "."
        valid = validate_config(repo)
        sys.exit(0 if valid else 1)

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
