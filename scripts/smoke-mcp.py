#!/usr/bin/env python3
"""Start each <app>-cli mcp over stdio and check initialize + tools/list.

Usage: scripts/smoke-mcp.py [--bin-dir DIR] [app ...]
Read-only: never calls a tool. Exits 1 if any server fails.
"""
import argparse
import json
import os
import subprocess
import sys

APPS = ["reminders", "calendar", "contacts", "notes", "maps", "weather", "freeform"]


def rpc(proc, msg_id, method, params=None):
    msg = {"jsonrpc": "2.0", "id": msg_id, "method": method}
    if params is not None:
        msg["params"] = params
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError(f"no reply to {method}")
    reply = json.loads(line)
    if "error" in reply:
        raise RuntimeError(f"{method}: {reply['error']}")
    return reply["result"]


def check(binary):
    proc = subprocess.Popen([binary, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True)
    try:
        init = rpc(proc, 1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                           "clientInfo": {"name": "smoke", "version": "1"}})
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        proc.stdin.flush()
        tools = rpc(proc, 2, "tools/list", {})["tools"]
        missing = [t["name"] for t in tools if not t.get("description") or "inputSchema" not in t]
        if missing:
            raise RuntimeError(f"tools without description/schema: {missing}")
        return init["serverInfo"]["name"], len(tools)
    finally:
        proc.kill()
        proc.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-dir", default=os.path.expanduser("~/.local/bin"))
    parser.add_argument("apps", nargs="*", default=APPS)
    args = parser.parse_args()
    failed = False
    for app in args.apps:
        binary = os.path.join(args.bin_dir, f"{app}-cli")
        if not os.access(binary, os.X_OK):
            print(f"skip  {app}: {binary} not installed")
            continue
        try:
            name, count = check(binary)
            print(f"ok    {app}: server {name}, {count} tools")
        except Exception as error:  # report every app, then fail
            failed = True
            print(f"FAIL  {app}: {error}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
