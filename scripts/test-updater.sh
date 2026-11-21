#!/bin/bash
# Offline tests for scripts/gesher GitHub updater (--check, --auto, --skip, doctor notice, up-to-date).
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gesher-updater-test.XXXXXX")"
server_pid=""
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; exit 1; }

# Create a fake installed layout under $work/prefix
prefix="${work}/prefix"
active="${prefix}/lib/gesher/active"
mkdir -p "$active" "${prefix}/bin"
cp "${root}/scripts/gesher" "${active}/gesher"
chmod +x "${active}/gesher"
ln -s "${active}/gesher" "${prefix}/bin/gesher"
cat >"${active}/install.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "${active}/install.sh"

# Fake weather-cli reporting version 1.2.0 and valid doctor JSON
cat >"${active}/weather-cli" <<'EOF'
#!/bin/bash
case "${1:-}" in
  --version) printf '1.2.0\n' ;;
  doctor) printf '{"app":"weather","version":"1.2.0","permission":"authorized"}\n' ;;
  *) printf '{"ok":true}\n' ;;
esac
EOF
chmod +x "${active}/weather-cli"

# Local HTTP redirect server simulating GitHub /releases/latest
port_file="${work}/port"
tag_file="${work}/tag"
printf 'v1.3.0\n' >"$tag_file"
/usr/bin/python3 - "$port_file" "$tag_file" <<'PY' &
import http.server, pathlib, sys
port_file, tag_file = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == "/releases/latest":
            tag = tag_file.read_text().strip()
            self.send_response(302)
            self.send_header("Location", f"/releases/tag/{tag}")
            self.end_headers()
        else:
            self.send_response(200)
            self.end_headers()
    def do_GET(self):
        self.do_HEAD()
    def log_message(self, *args):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(srv.server_address[1]))
srv.serve_forever()
PY
server_pid=$!

for _ in $(seq 1 40); do [[ -s "$port_file" ]] && break; sleep 0.1; done
port="$(cat "$port_file")"
[[ -n "$port" ]] || fail "mock redirect server did not start"

export GESHER_RELEASES_URL="http://127.0.0.1:${port}/releases/latest"
export GESHER_CONFIG="${work}/config.json"
export GESHER_UPDATE_CACHE="${work}/update-check.json"

# Seed an existing config section to make sure updater settings preserve it.
printf '{"weather":{"location":"Haifa"}}\n' >"$GESHER_CONFIG"

# 1. --check --json detects newer version 1.3.0
out="$("${prefix}/bin/gesher" update --check --json)"
/usr/bin/python3 - "$out" <<'PY' || fail "check --json expected updateAvailable=true, got: $out"
import json, sys
d = json.loads(sys.argv[1])
assert d["installed"] == "1.2.0" and d["latest"] == "1.3.0" and d["updateAvailable"] is True and d["policy"] == "ask"
PY
pass "update --check --json detects newer GitHub release"

# 2. doctor human output mentions available update; doctor --json stays pure JSON
doc_human="$("${prefix}/bin/gesher" doctor)"
grep -q "Update available: 1.2.0 -> 1.3.0" <<<"$doc_human" || fail "doctor did not show update notice"
doc_json="$("${prefix}/bin/gesher" doctor --json)"
/usr/bin/python3 - "$doc_json" <<'PY' || fail "doctor --json was not valid JSON"
import json, sys
arr = json.loads(sys.argv[1])
assert isinstance(arr, list) and arr[0]["app"] == "weather"
PY
pass "doctor shows update notice in human mode and keeps --json clean"

# 3. --auto and --skip persist in config.json without losing unrelated app settings
"${prefix}/bin/gesher" update --auto always >/dev/null
"${prefix}/bin/gesher" update --skip 1.3.0 >/dev/null
/usr/bin/python3 - "$GESHER_CONFIG" <<'PY' || fail "config.json missing expected keys"
import json, pathlib, sys
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert d["weather"]["location"] == "Haifa"
assert d["updates"]["mode"] == "always"
assert d["updates"]["skippedVersion"] == "1.3.0"
PY
pass "update --auto and --skip preserve unrelated config.json keys"

# 4. Invalid --auto mode exits 64
if "${prefix}/bin/gesher" update --auto bogus >/dev/null 2>&1; then
  fail "invalid --auto mode should have exited non-zero"
fi
pass "invalid --auto mode is rejected"

# 5. --skip clear resets skippedVersion
"${prefix}/bin/gesher" update --skip clear >/dev/null
"${prefix}/bin/gesher" update --auto ask >/dev/null
/usr/bin/python3 - "$GESHER_CONFIG" <<'PY' || fail "skip clear did not clear skippedVersion"
import json, pathlib, sys
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert "skippedVersion" not in d["updates"] and d["updates"]["mode"] == "ask"
PY
pass "update --skip clear resets skippedVersion"

# 6. When server serves v1.2.0, gesher update reports already up to date without installing
printf 'v1.2.0\n' >"$tag_file"
up_out="$("${prefix}/bin/gesher" update)"
grep -q "already up to date" <<<"$up_out" || fail "expected up-to-date message, got: $up_out"
pass "gesher update skips download when already on latest release"

printf 'updater: all tests passed\n'

