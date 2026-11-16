#!/usr/bin/env python3
"""Package each app's MCP server as an MCP Bundle (.mcpb) and write its MCP Registry entry.

    scripts/package-mcpb.py dist/gesher-<version>-macos-arm64.tar.gz [--out dist/mcpb]

The bundles reuse the signed binaries of a release archive (built by `make dist`), so a bundle
runs exactly what that release ships. Each bundle holds one server: manifest.json,
server/<app>-cli, icon.png and LICENSE. The registry entries in registry/<app>.json point at
the bundles attached to the GitHub release `v<version>` and carry their SHA-256; publish them
with `mcp-publisher publish registry/<app>.json`.
"""
import argparse, hashlib, json, os, pathlib, shutil, subprocess, sys, tarfile, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = "https://github.com/EphraimElgrabli/gesher"
NAMESPACE = "io.github.EphraimElgrabli"
APPLE_PRIVACY = "https://www.apple.com/legal/privacy/"

# Registry descriptions are limited to 100 characters.
APPS = {
    "reminders": ("Reminders", "Apple Reminders on macOS: tasks, lists, sections, tags, subtasks, smart lists and templates."),
    "calendar": ("Calendar", "Apple Calendar on macOS: agenda, free time, events, repeating events, alerts and invitations."),
    "contacts": ("Contacts", "Apple Contacts on macOS: search by name, phone or email, edit cards, groups, birthdays, vCard."),
    "notes": ("Notes", "Apple Notes on macOS as Markdown: folders, checklists, tables, tags and attachments."),
    "maps": ("Maps", "Apple Maps on macOS, read-only: place search, details, opening hours, routes and travel times."),
    "weather": ("Weather", "Apple Weather on macOS: forecasts, next-hour rain, severe-weather alerts, air quality, places."),
    "freeform": ("Freeform", "Apple Freeform on macOS: read and search boards, create boards, add text, links and files."),
}
# Apps whose servers send queries to Apple's online services.
ONLINE = {"maps", "weather"}


def tools(binary: pathlib.Path) -> list:
    request = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n'
    env = {**os.environ, "GESHER_DISCLAIM": "0"}
    out = subprocess.run([str(binary), "mcp"], input=request, capture_output=True, text=True, env=env, check=True)
    listed = json.loads(out.stdout)["result"]["tools"]
    return [{"name": t["name"], "description": t["description"]} for t in listed]


def manifest(app: str, version: str, binary: pathlib.Path) -> dict:
    title, description = APPS[app]
    data = {
        "manifest_version": "0.3",
        "name": f"gesher-{app}",
        "display_name": f"Gesher {title}",
        "version": version,
        "description": description,
        "long_description": (
            f"Lets an AI agent work with Apple {title} on this Mac through the frameworks the app is built on, "
            "including private frameworks Apple doesn't document for third-party use (a macOS update may break "
            "them). Runs locally: no Gesher servers, accounts or telemetry. Requires an Apple silicon Mac with "
            "macOS 26 or later (tested on macOS 27). The first use asks for the macOS permission the app needs; "
            f"see {REPO}/blob/main/docs/permissions.md. For every Mac app at once, use the installer in the README."
        ),
        "author": {"name": "Ephraim Elgrabli", "url": "https://github.com/EphraimElgrabli"},
        "repository": {"type": "git", "url": f"{REPO}.git"},
        "homepage": REPO,
        "documentation": f"{REPO}/blob/main/apps/{app}/README.md",
        "support": f"{REPO}/blob/main/SECURITY.md",
        "icon": "icon.png",
        "server": {
            "type": "binary",
            "entry_point": f"server/{app}-cli",
            "mcp_config": {"command": f"${{__dirname}}/server/{app}-cli", "args": ["mcp"], "env": {}},
        },
        "tools": tools(binary),
        "tools_generated": False,
        "keywords": ["apple", "macos", app, "mcp", "gesher"],
        "license": "GPL-3.0-only",
        "compatibility": {"platforms": ["darwin"]},
    }
    if app in ONLINE:
        data["privacy_policies"] = [APPLE_PRIVACY]
    return data


def server_json(app: str, version: str, sha: str) -> dict:
    title, description = APPS[app]
    return {
        "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
        "name": f"{NAMESPACE}/gesher-{app}",
        "title": f"Gesher {title}",
        "description": description,
        "repository": {"url": REPO, "source": "github"},
        "websiteUrl": REPO,
        "version": version,
        "packages": [
            {
                "registryType": "mcpb",
                "identifier": f"{REPO}/releases/download/v{version}/gesher-{app}-{version}.mcpb",
                "fileSha256": sha,
                "transport": {"type": "stdio"},
            }
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "dist" / "mcpb")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        with tarfile.open(args.archive) as archive:
            archive.extractall(scratch, filter="data")
        (stage,) = pathlib.Path(scratch).iterdir()
        for app in APPS:
            binary = stage / "bin" / f"{app}-cli"
            version = subprocess.run([str(binary), "--version"], capture_output=True, text=True, check=True).stdout.strip()
            bundle = args.out / f"gesher-{app}-{version}.mcpb"
            entries = {
                "manifest.json": (json.dumps(manifest(app, version, binary), indent=2) + "\n").encode(),
                f"server/{app}-cli": binary.read_bytes(),
                "icon.png": (ROOT / "plugins" / f"gesher-{app}" / "assets" / "icon.png").read_bytes(),
                "LICENSE": (ROOT / "LICENSE").read_bytes(),
            }
            with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as out:
                for name, data in entries.items():
                    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                    info.create_system = 3  # Unix, so the mode below is honored
                    info.external_attr = (0o755 if name.startswith("server/") else 0o644) << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    out.writestr(info, data)
            sha = hashlib.sha256(bundle.read_bytes()).hexdigest()
            entry = ROOT / "registry" / f"{app}.json"
            entry.parent.mkdir(exist_ok=True)
            entry.write_text(json.dumps(server_json(app, version, sha), indent=2) + "\n")
            print(f"{bundle.relative_to(ROOT) if bundle.is_relative_to(ROOT) else bundle}  {sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
