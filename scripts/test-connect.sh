#!/bin/bash
# Tests for connect.sh against throwaway home folders: plain JSON, JSON with comments (Zed, VS
# Code), a symlinked settings file, an empty file, idempotent re-runs and removal that restores the
# original text. Never touches the real home folder. Run by `make lint`.
set -euo pipefail

connect="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/connect.sh"
home="$(mktemp -d "${TMPDIR:-/tmp}/gesher-connect-test.XXXXXX")"
trap 'rm -rf "$home"' EXIT
failures=0

run() { env -i HOME="$home" PATH=/usr/bin:/bin GESHER_NO_CLIPBOARD=1 bash "$connect" --bin-dir /opt/gesher/bin "$@" </dev/null; }
check() {
  if eval "$2"; then printf '  ok   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); fi
}

zed="${home}/.config/zed/settings.json"
vscode="${home}/Library/Application Support/Code/User/mcp.json"
cursor="${home}/.cursor/mcp.json"
lmstudio="${home}/.lmstudio/mcp.json"
mkdir -p "$(dirname "$zed")" "$(dirname "$vscode")" "$(dirname "$cursor")" "$(dirname "$lmstudio")" "${home}/dotfiles"
cat >"$zed" <<'JSON'
// Zed settings
{
  "theme": "One Dark", // dark
  "context_servers": {
    // mine
    "postgres": {
      "command": "pg-mcp", "args": [] /* none */
    },
  },
  "url": "http://example.com//path",
}
JSON
printf '{\n\t// VS Code\n\t"servers": {\n\t\t"github": {"type": "http", "url": "https://example.com"}\n\t},\n\t"inputs": []\n}\n' >"$vscode"
printf '{"mcpServers": {"other": {"command": "other"}}}\n' >"${home}/dotfiles/mcp.json"
ln -s "${home}/dotfiles/mcp.json" "$cursor"
: >"$lmstudio"
zed_before="$(cat "$zed")" vscode_before="$(cat "$vscode")"

run zed vscode cursor lmstudio --apps weather,maps >/dev/null
check "Zed: servers added, comments kept" 'grep -q "\"gesher-weather\": { \"command\": \"/opt/gesher/bin/weather-cli\"" "$zed" && grep -q "// mine" "$zed" && grep -q postgres "$zed"'
check "VS Code: stdio servers added next to the existing one" 'grep -q "\"type\": \"stdio\"" "$vscode" && grep -q github "$vscode"'
check "Cursor: symlink kept, target edited" '[[ -L "$cursor" ]] && grep -q gesher-maps "${home}/dotfiles/mcp.json" && grep -q other "${home}/dotfiles/mcp.json"'
check "LM Studio: empty file filled in" 'grep -q gesher-weather "$lmstudio"'
check "all files still parse" '[[ "$(run --list | grep -cE "^(zed|vscode|cursor|lmstudio) .*connected \(weather, maps\)")" == 4 ]]'
check "status lists the connected apps" '[[ "$(run --list | grep -E "^zed ")" == *"connected (weather, maps)"* ]]'

run cursor --apps reminders >/dev/null && run --remove cursor --apps reminders >/dev/null
run cursor >/dev/null
check "Cursor gets three apps by default" '[[ "$(grep -c gesher- "${home}/dotfiles/mcp.json")" == 5 ]]'
run --remove cursor >/dev/null
run cursor --apps weather,maps >/dev/null

run zed --apps weather,maps >/dev/null
check "re-running changes nothing" '[[ "$(grep -c gesher- "$zed")" == 2 ]]'
run zed >/dev/null
check "connecting all apps adds the rest once" '[[ "$(grep -c gesher- "$zed")" == 7 ]]'

run --remove zed vscode cursor lmstudio >/dev/null
check "Zed: removal restores the original text" '[[ "$(cat "$zed")" == "$zed_before" ]]'
check "VS Code: removal restores the original text" '[[ "$(cat "$vscode")" == "$vscode_before" ]]'
check "Cursor: other servers kept" '! grep -q gesher- "${home}/dotfiles/mcp.json" && grep -q other "${home}/dotfiles/mcp.json"'
check "backups were made" '[[ -n "$(ls "${home}/.config/gesher/backups/connect")" ]]'
check "backups are private" '[[ "$(stat -f %Lp "${home}/.config/gesher/backups/connect")" == 700 && -z "$(find "${home}/.config/gesher/backups/connect" -type f ! -perm 600)" ]]'

printf '{"mcpServers": [1, 2]}\n' >"$cursor"
check "an unexpected shape is left alone" '! run cursor >/dev/null 2>&1 && [[ "$(cat "$cursor")" == "{\"mcpServers\": [1, 2]}" ]]'
check "no terminal: asks nothing, changes nothing" 'run | grep "No terminal" >/dev/null'
# With no AI apps installed at all (bash 3.2 and set -u must cope with empty lists).
no_apps="$(mktemp "${TMPDIR:-/tmp}/gesher-connect-noapps.XXXXXX")"
sed 's#/Applications/#/nonexistent/#g; s#"${support}/#"/nonexistent/#g' "$connect" >"$no_apps"
empty="$(mktemp -d "${TMPDIR:-/tmp}/gesher-connect-empty.XXXXXX")"
check "no AI apps: --remove succeeds" 'env -i HOME="$empty" PATH=/usr/bin:/bin bash "$no_apps" --remove --bin-dir /x >/dev/null 2>&1'
check "no AI apps: connect prints the snippet" 'env -i HOME="$empty" PATH=/usr/bin:/bin bash "$no_apps" --all --bin-dir /x | grep mcpServers >/dev/null'
rm -rf "$no_apps" "$empty"

if [[ "$failures" -gt 0 ]]; then printf '%d connect test(s) failed\n' "$failures"; exit 1; fi
printf 'connect.sh: all tests passed\n'
