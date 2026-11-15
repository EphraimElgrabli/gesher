#!/bin/bash
# gesher connect: register Gesher's MCP servers with the AI apps on this Mac.
#
# Each AI app keeps its MCP servers in its own settings file (or has its own command for adding
# one). This script finds the apps that are installed, then adds or removes one server per Mac app,
# named gesher-<app>, pointing at PREFIX/bin/<app>-cli. Every settings file it changes is backed up
# first to ~/.config/gesher/backups/connect/. Entries that are not gesher-* are never touched.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gesher connect [AI apps...] [options]

  gesher connect                 find your AI apps and ask which ones to connect
  gesher connect --all           connect every AI app found, without asking
  gesher connect cursor claude-desktop
  gesher connect --list          show the AI apps found and whether Gesher is connected
  gesher connect --remove [AI apps...]   disconnect (all, if none are named)
  gesher connect --print         print the MCP settings JSON for any other app

Options:
  --apps LIST      only these Mac apps, e.g. reminders,calendar (default: all eight)
  --bin-dir DIR    where the <app>-cli commands are (default: next to this install)
  -y, --yes        don't ask (same as --all when no AI apps are named)
  -h, --help       show this help

AI apps: claude-desktop claude-code codex cursor vscode vscode-insiders windsurf gemini antigravity
         lmstudio opencode zed kiro warp cline
EOF
}

all_apps=(reminders calendar contacts notes maps weather freeform)
clients=(claude-desktop claude-code codex cursor vscode vscode-insiders windsurf gemini antigravity lmstudio opencode zed kiro warp cline)
support="${HOME}/Library/Application Support"

if [[ -t 1 ]]; then
  bold=$'\033[1m' dim=$'\033[2m' green=$'\033[32m' yellow=$'\033[33m' cyan=$'\033[36m' reset=$'\033[0m'
else
  bold="" dim="" green="" yellow="" cyan="" reset=""
fi
ok() { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
skip() { printf '  %s–%s %s\n' "$dim" "$reset" "$*"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

display_name() {
  case "$1" in
    claude-desktop) echo "Claude Desktop" ;; claude-code) echo "Claude Code" ;; codex) echo "Codex" ;;
    cursor) echo "Cursor" ;; vscode) echo "VS Code" ;; vscode-insiders) echo "VS Code Insiders" ;;
    windsurf) echo "Windsurf / Devin" ;; gemini) echo "Gemini CLI" ;; antigravity) echo "Antigravity" ;;
    lmstudio) echo "LM Studio" ;; opencode) echo "opencode" ;; zed) echo "Zed" ;; kiro) echo "Kiro" ;;
    warp) echo "Warp" ;; cline) echo "Cline" ;; *) echo "$1" ;;
  esac
}

# The settings file of an app that is configured through a file ("" for command-based apps).
config_file() {
  case "$1" in
    claude-desktop) echo "${support}/Claude/claude_desktop_config.json" ;;
    cursor) echo "${HOME}/.cursor/mcp.json" ;;
    vscode) echo "${support}/Code/User/mcp.json" ;;
    vscode-insiders) echo "${support}/Code - Insiders/User/mcp.json" ;;
    windsurf)
      # Windsurf became Devin Desktop in 2026; it reads both paths and writes the Devin one.
      if app_bundle Devin || [[ -d "${HOME}/.config/devin" ]]; then echo "${HOME}/.config/devin/mcp_config.json"
      else echo "${HOME}/.codeium/windsurf/mcp_config.json"; fi ;;
    gemini) echo "${HOME}/.gemini/settings.json" ;;
    antigravity) echo "${HOME}/.gemini/config/mcp_config.json" ;;
    kiro) echo "${HOME}/.kiro/settings/mcp.json" ;;
    warp) echo "${HOME}/.warp/.mcp.json" ;;
    cline)
      # The VS Code extension's settings when it is installed, else the Cline CLI's.
      local candidate
      for candidate in "${support}/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" \
        "${support}/Code - Insiders/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"; do
        [[ -f "$candidate" ]] && { echo "$candidate"; return; }
      done
      echo "${CLINE_MCP_SETTINGS_PATH:-${HOME}/.cline/data/settings/cline_mcp_settings.json}" ;;
    lmstudio) echo "${HOME}/.lmstudio/mcp.json" ;;
    opencode)
      if [[ -f "${HOME}/.config/opencode/opencode.jsonc" ]]; then echo "${HOME}/.config/opencode/opencode.jsonc"
      else echo "${HOME}/.config/opencode/opencode.json"; fi ;;
    zed) echo "${HOME}/.config/zed/settings.json" ;;
    *) echo "" ;;
  esac
}

# The settings key that holds the servers, and the shape of one entry.
config_style() {
  case "$1" in
    vscode | vscode-insiders) echo servers ;;
    opencode) echo opencode ;;
    zed) echo zed ;;
    *) echo mcpServers ;;
  esac
}

app_bundle() {
  local name
  for name in "$@"; do
    [[ -d "/Applications/${name}.app" || -d "${HOME}/Applications/${name}.app" ]] && return 0
  done
  return 1
}

# The ChatGPT desktop app is built on Codex (bundle id com.openai.codex) and shares its settings.
chatgpt_is_codex() {
  local app
  for app in "/Applications/ChatGPT.app" "${HOME}/Applications/ChatGPT.app"; do
    [[ "$(plutil -extract CFBundleIdentifier raw -o - "${app}/Contents/Info.plist" 2>/dev/null)" == com.openai.codex ]] && return 0
  done
  return 1
}

installed() {
  case "$1" in
    claude-desktop) app_bundle Claude || [[ -d "${support}/Claude" ]] ;;
    claude-code) command -v claude >/dev/null 2>&1 ;;
    codex) command -v codex >/dev/null 2>&1 || app_bundle Codex || chatgpt_is_codex ;;
    cursor) app_bundle Cursor || [[ -d "${HOME}/.cursor" ]] ;;
    vscode) app_bundle "Visual Studio Code" || [[ -d "${support}/Code/User" ]] ;;
    vscode-insiders) app_bundle "Visual Studio Code - Insiders" || [[ -d "${support}/Code - Insiders/User" ]] ;;
    windsurf) app_bundle Windsurf Devin || [[ -d "${HOME}/.codeium/windsurf" || -d "${HOME}/.config/devin" ]] ;;
    gemini) command -v gemini >/dev/null 2>&1 || [[ -f "${HOME}/.gemini/settings.json" ]] ;;
    antigravity) app_bundle Antigravity "Antigravity IDE" || [[ -d "${HOME}/.gemini/config" ]] ;;
    kiro) app_bundle Kiro || [[ -d "${HOME}/.kiro" ]] ;;
    warp) app_bundle Warp || [[ -d "${HOME}/.warp" ]] ;;
    cline) command -v cline >/dev/null 2>&1 || [[ -d "${HOME}/.cline" ]] || [[ -f "$(config_file cline)" ]] ;;
    lmstudio) app_bundle "LM Studio" || [[ -d "${HOME}/.lmstudio" ]] ;;
    opencode) command -v opencode >/dev/null 2>&1 || [[ -x "${HOME}/.opencode/bin/opencode" ]] || [[ -d "${HOME}/.config/opencode" ]] ;;
    zed) app_bundle Zed || [[ -d "${HOME}/.config/zed" ]] ;;
    *) return 1 ;;
  esac
}

# Settings files are edited in JavaScriptCore (osascript -l JavaScript, part of every macOS, used
# here only as a JSON engine). Edits are made to the text: only the gesher-* entries are added or
# removed, so the rest of the file keeps its formatting, key order and comments (JSONC, as in Zed
# or VS Code). A symlinked file is edited where it points. The result is parsed again before it is
# written; anything unexpected leaves the file alone and prints "unparsable".
#   json_edit FILE STYLE add|remove|status BIN APPS...
json_edit() {
  osascript -l JavaScript - "$@" <<'JS' 2>&1
ObjC.import('Foundation');
// Blank out comments and trailing commas, keeping every other character at its offset.
function stripJsonc(text) {
  let out = '', i = 0, inString = false;
  while (i < text.length) {
    const c = text[i], n = text[i + 1];
    if (inString) {
      out += c;
      if (c === '\\') { out += n || ''; i += 2; continue; }
      if (c === '"') inString = false;
      i++;
    } else if (c === '"') { inString = true; out += c; i++; }
    else if (c === '/' && n === '/') { while (i < text.length && text[i] !== '\n') { out += ' '; i++; } }
    else if (c === '/' && n === '*') {
      const end = text.indexOf('*/', i + 2), stop = end < 0 ? text.length : end + 2;
      out += text.slice(i, stop).replace(/[^\n]/g, ' '); i = stop;
    } else { out += c; i++; }
  }
  return out.replace(/,(\s*[}\]])/g, ' $1');
}
function stringEnd(s, i) {
  for (i++; i < s.length; i++) {
    if (s[i] === '\\') i++;
    else if (s[i] === '"') return i + 1;
  }
  throw new Error('unterminated string');
}
function valueEnd(s, i) {
  if (s[i] === '"') return stringEnd(s, i);
  if (s[i] === '{' || s[i] === '[') {
    let depth = 0;
    while (i < s.length) {
      const c = s[i];
      if (c === '"') { i = stringEnd(s, i); continue; }
      if (c === '{' || c === '[') depth++;
      if ((c === '}' || c === ']') && --depth === 0) return i + 1;
      i++;
    }
    throw new Error('unbalanced');
  }
  while (i < s.length && !/[,}\]\s]/.test(s[i])) i++;
  return i;
}
// The members of the object whose '{' is at `open` in the stripped text.
function members(s, open) {
  const list = [];
  let i = open + 1;
  for (;;) {
    while (i < s.length && /[\s,]/.test(s[i])) i++;
    if (s[i] === '}') return { list, close: i };
    if (s[i] !== '"') throw new Error('not an object');
    const start = i, keyEnd = stringEnd(s, i), key = JSON.parse(s.slice(i, keyEnd));
    i = keyEnd;
    while (/\s/.test(s[i])) i++;
    if (s[i++] !== ':') throw new Error('not an object');
    while (/\s/.test(s[i])) i++;
    const value = i;
    i = valueEnd(s, i);
    list.push({ key, start, value, end: i });
  }
}
// One-line JSON with a space after each colon and comma: { "command": "...", "args": ["mcp"] }
function inline(value) {
  return JSON.stringify(value, null, 1).replace(/\n\s*/g, ' ').replace(/\[ /g, '[').replace(/ \]/g, ']');
}
function indentAt(s, i) {
  const line = s.lastIndexOf('\n', i) + 1;
  return s.slice(line, i).match(/^[ \t]*/)[0];
}
function run(argv) {
  const [path, style, action, bin, ...apps] = argv;
  const file = ObjC.unwrap($(path).stringByResolvingSymlinksInPath);
  const fm = $.NSFileManager.defaultManager;
  let text = '';
  if (fm.fileExistsAtPath(file)) {
    text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(file, $.NSUTF8StringEncoding, null)) || '';
  }
  const key = style === 'opencode' ? 'mcp' : style === 'zed' ? 'context_servers' : style;
  const entry = (app) => {
    const command = `${bin}/${app}-cli`;
    if (style === 'servers') return { type: 'stdio', command, args: ['mcp'] };
    if (style === 'opencode') return { type: 'local', command: [command, 'mcp'], enabled: true };
    return { command, args: ['mcp'] };
  };
  if (text.trim() === '') text = '{}\n';
  let data;
  try { data = JSON.parse(stripJsonc(text)); } catch (e) { return 'unparsable'; }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return 'unparsable';
  const current = data[key] && typeof data[key] === 'object' && !Array.isArray(data[key]) ? data[key] : null;
  if (key in data && !current) return 'unparsable';
  // enabledPlugins (Claude Code) maps "gesher-<app>@gesher" to true or false.
  const ours = Object.keys(current || {}).filter((name) => /^gesher-/.test(name) && (key !== 'enabledPlugins' || current[name] === true));
  if (action === 'status') return ours.length ? ours.map((n) => n.slice(7)).join(',') : 'none';
  const wanted = action === 'add' ? apps : [];
  const unchanged = apps.every((app) => JSON.stringify((current || {})[`gesher-${app}`]) === JSON.stringify(action === 'add' ? entry(app) : undefined));
  if (unchanged) return 'ok';
  try {
    // 1. Remove the gesher-<app> entries for these apps, one at a time.
    for (const app of apps) {
      const s = stripJsonc(text), root = members(s, s.indexOf('{'));
      const servers = root.list.find((m) => m.key === key);
      if (!servers) break;
      const m = members(s, servers.value).list.find((x) => x.key === `gesher-${app}`);
      if (!m) continue;
      let j = m.end;
      while (/\s/.test(s[j])) j++;
      if (s[j] === ',') {
        const line = s.lastIndexOf('\n', m.start) + 1;
        const from = /^\s*$/.test(s.slice(line, m.start)) ? line : m.start;
        let to = j + 1;
        if (from === line) { while (s[to] === ' ' || s[to] === '\t') to++; if (s[to] === '\n') to++; }
        text = text.slice(0, from) + text.slice(to);
      } else {
        let k = m.start - 1;
        while (k > servers.value && /\s/.test(s[k])) k--;
        text = text.slice(0, s[k] === ',' ? k : m.start) + text.slice(m.end);
      }
    }
    // An object emptied by the removals collapses to {} instead of keeping a blank line.
    if (!wanted.length) {
      const s = stripJsonc(text), root = members(s, s.indexOf('{'));
      const servers = root.list.find((m) => m.key === key);
      if (servers) {
        const inner = members(s, servers.value);
        if (!inner.list.length && /^\{\s*\}$/.test(text.slice(servers.value, inner.close + 1))) {
          text = text.slice(0, servers.value) + '{}' + text.slice(inner.close + 1);
        }
      }
    }
    // 2. Insert the new entries at the top of the servers object (created if missing).
    if (wanted.length) {
      const s = stripJsonc(text), open = s.indexOf('{'), root = members(s, open);
      const servers = root.list.find((m) => m.key === key);
      const rootIndent = root.list.length ? indentAt(s, root.list[0].start) : '  ';
      if (servers) {
        const inner = members(s, servers.value);
        const indent = inner.list.length ? indentAt(s, inner.list[0].start) : indentAt(s, servers.start) + rootIndent;
        const lines = wanted.map((app) => `${indent}${JSON.stringify(`gesher-${app}`)}: ${inline(entry(app))}`).join(',\n');
        const tail = inner.list.length ? ',' : `\n${indentAt(s, servers.start)}`;
        text = text.slice(0, servers.value + 1) + `\n${lines}${tail}` + text.slice(servers.value + 1);
      } else {
        const lines = wanted.map((app) => `${rootIndent}${rootIndent}${JSON.stringify(`gesher-${app}`)}: ${inline(entry(app))}`).join(',\n');
        const tail = root.list.length ? ',' : '\n';
        text = text.slice(0, open + 1) + `\n${rootIndent}${JSON.stringify(key)}: {\n${lines}\n${rootIndent}}${tail}` + text.slice(open + 1);
      }
    }
    const check = JSON.parse(stripJsonc(text))[key] || {};
    if (!apps.every((app) => JSON.stringify(check[`gesher-${app}`]) === JSON.stringify(action === 'add' ? entry(app) : undefined))) return 'unparsable';
  } catch (e) { return 'unparsable'; }
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(file).stringByDeletingLastPathComponent, true, $(), null);
  return $(text).writeToFileAtomicallyEncodingError(file, true, $.NSUTF8StringEncoding, null) ? 'ok' : 'write-failed';
}
JS
}

# Comma-joined app names (one per input line), in the usual app order.
in_app_order() {
  local names app out=()
  names=" $(tr '\n' ' ') "
  for app in "${all_apps[@]}"; do [[ "$names" == *" ${app} "* ]] && out+=("$app"); done
  local IFS=,
  echo "${out[*]-}"
}

count_word() { if [[ "$1" == 1 ]]; then printf '1 %s' "$2"; else printf '%s %ss' "$1" "$2"; fi; }

backup() {
  [[ -f "$1" ]] || return 0
  local dir="${HOME}/.config/gesher/backups/connect"
  local copy
  mkdir -p "$dir"
  # The copies can hold other MCP servers' API keys: only the user may read them.
  chmod 700 "${HOME}/.config/gesher/backups" "$dir"
  copy="${dir}/$(date -u +%Y%m%dT%H%M%SZ)-$2-$(basename "$1")"
  cp -p "$1" "$copy"
  chmod 600 "$copy"
}

snippet() {
  local style="$1" app first=1 bin="${bin_dir//\\/\\\\}"
  bin="${bin//\"/\\\"}"
  case "$style" in
    servers) printf '{\n  "servers": {\n' ;;
    opencode) printf '{\n  "mcp": {\n' ;;
    zed) printf '{\n  "context_servers": {\n' ;;
    *) printf '{\n  "mcpServers": {\n' ;;
  esac
  for app in "${apps[@]}"; do
    [[ "$first" == 1 ]] || printf ',\n'
    first=0
    case "$style" in
      servers) printf '    "gesher-%s": { "type": "stdio", "command": "%s/%s-cli", "args": ["mcp"] }' "$app" "$bin" "$app" ;;
      opencode) printf '    "gesher-%s": { "type": "local", "command": ["%s/%s-cli", "mcp"], "enabled": true }' "$app" "$bin" "$app" ;;
      zed) printf '    "gesher-%s": { "command": "%s/%s-cli", "args": ["mcp"] }' "$app" "$bin" "$app" ;;
      *) printf '    "gesher-%s": { "command": "%s/%s-cli", "args": ["mcp"] }' "$app" "$bin" "$app" ;;
    esac
  done
  printf '\n  }\n}\n'
}

# Current connection state: "none", or the comma-separated connected apps.
status() {
  local client="$1" file out
  case "$client" in
    claude-code)
      # User-scope servers: mcpServers at the top of ~/.claude.json; plugins: ~/.claude/settings.json.
      out="$({ [[ -f "${HOME}/.claude.json" ]] && json_edit "${HOME}/.claude.json" mcpServers status "$bin_dir"
        [[ -f "${HOME}/.claude/settings.json" ]] && json_edit "${HOME}/.claude/settings.json" enabledPlugins status "$bin_dir"
      } | tr ',' '\n' | sed 's/@.*//' | in_app_order)" || true
      echo "${out:-none}" ;;
    codex)
      local home="${CODEX_HOME:-${HOME}/.codex}"
      out="$({ ls -1 "${home}/plugins" 2>/dev/null; grep -oE '^\[mcp_servers\.gesher-[a-z]+\]' "${home}/config.toml" 2>/dev/null; } \
        | grep -oE 'gesher-[a-z]+' | sed 's/^gesher-//' | in_app_order)" || true
      echo "${out:-none}" ;;
    *)
      file="$(config_file "$client")"
      [[ -f "$file" ]] || { echo none; return; }
      json_edit "$file" "$(config_style "$client")" status "$bin_dir" ;;
  esac
}

connect_one() {
  local client="$1" name file style result app
  local apps=("${apps[@]}")
  # Cursor and Windsurf work best with fewer tools: connect the three most useful apps unless
  # --apps says otherwise.
  if [[ -z "$selected_apps" && ( "$client" == cursor || "$client" == windsurf ) ]]; then
    apps=(reminders calendar notes)
    printf '  %si%s %s works best with fewer tools, so it gets Reminders, Calendar and Notes.\n' "$cyan" "$reset" "$(display_name "$client")"
    printf '    Add more with: %sgesher connect %s --apps reminders,calendar,notes,maps,...%s\n' "$cyan" "$client" "$reset"
  fi
  name="$(display_name "$client")"
  case "$client" in
    claude-code)
      # Plugins bring a skill for each app on top of its MCP server; their .mcp.json expects ~/.local/bin.
      if [[ "$bin_dir" == "${HOME}/.local/bin" ]] \
        && { claude plugin marketplace list 2>/dev/null | grep -qw gesher \
          || claude plugin marketplace add EphraimElgrabli/gesher >/dev/null 2>&1; }; then
        for app in "${apps[@]}"; do
          claude mcp remove --scope user "gesher-${app}" >/dev/null 2>&1 || true # no duplicate server
          claude plugin install "gesher-${app}@gesher" >/dev/null 2>&1 || { warn "${name}: could not install the gesher-${app} plugin"; return 1; }
        done
        ok "${name}: installed $(count_word "${#apps[@]}" plugin) ${dim}(restart Claude Code)${reset}"
      else
        for app in "${apps[@]}"; do
          claude mcp remove --scope user "gesher-${app}" >/dev/null 2>&1 || true
          claude mcp add --scope user --transport stdio "gesher-${app}" -- "${bin_dir}/${app}-cli" mcp >/dev/null \
            || { warn "${name}: claude mcp add gesher-${app} failed"; return 1; }
        done
        ok "${name}: added $(count_word "${#apps[@]}" "MCP server") ${dim}(restart Claude Code)${reset}"
      fi ;;
    codex)
      "${here}/install-plugins.sh" --bin-dir "$bin_dir" --apps "$(IFS=,; echo "${apps[*]}")" --quiet >/dev/null \
        || { warn "${name}: plugin install failed (try: gesher plugins)"; return 1; }
      # With the codex command on the PATH, install-plugins.sh has already enabled them.
      if command -v codex >/dev/null 2>&1; then
        ok "${name}: installed $(count_word "${#apps[@]}" plugin) ${dim}(restart Codex)${reset}"
      else
        ok "${name}: installed $(count_word "${#apps[@]}" plugin) ${dim}(restart Codex, then turn them on under Plugins)${reset}"
      fi ;;
    *)
      file="$(config_file "$client")"
      style="$(config_style "$client")"
      backup "$file" "$client"
      result="$(json_edit "$file" "$style" add "$bin_dir" "${apps[@]}")"
      if [[ "$result" == ok ]]; then
        ok "${name}: added $(count_word "${#apps[@]}" "MCP server") to ${file/#${HOME}/~} ${dim}(restart ${name})${reset}"
      else
        warn "${name}: ${file/#${HOME}/~} isn't valid JSON, so it was left as is."
        local where=""
        # Copy the snippet only for a person at a terminal, never for scripts or tests.
        if [[ -t 1 && -z "${GESHER_NO_CLIPBOARD:-}" ]] && command -v pbcopy >/dev/null && snippet "$style" | pbcopy; then
          where=" (it is on your clipboard)"
        fi
        printf '    Add this to it by hand%s:\n\n' "$where"
        snippet "$style" | sed 's/^/      /'
        printf '\n'
        return 1
      fi ;;
  esac
}

remove_one() {
  local client="$1" name file result app
  name="$(display_name "$client")"
  case "$client" in
    claude-code)
      [[ "$(status claude-code)" == none ]] && { skip "${name}: not connected"; return 0; }
      for app in "${apps[@]}"; do
        claude plugin uninstall "gesher-${app}@gesher" >/dev/null 2>&1 || true
        claude mcp remove --scope user "gesher-${app}" >/dev/null 2>&1 || true
      done
      ok "${name}: disconnected" ;;
    codex)
      [[ "$(status codex)" == none ]] && { skip "${name}: not connected"; return 0; }
      "${here}/install-plugins.sh" --uninstall --bin-dir "$bin_dir" --apps "$(IFS=,; echo "${apps[*]}")" >/dev/null || true
      ok "${name}: disconnected" ;;
    *)
      file="$(config_file "$client")"
      [[ -f "$file" ]] || { skip "${name}: not connected"; return 0; }
      [[ "$(status "$client")" == none ]] && { skip "${name}: not connected"; return 0; }
      backup "$file" "$client"
      result="$(json_edit "$file" "$(config_style "$client")" remove "$bin_dir" "${apps[@]}")"
      if [[ "$result" == ok ]]; then ok "${name}: disconnected"; else warn "${name}: remove the gesher-* entries from ${file/#${HOME}/~} by hand"; return 1; fi ;;
  esac
}

ask() {
  # Read from the terminal even when this script's stdin is a pipe (curl | bash).
  local answer
  (: </dev/tty) 2>/dev/null || return 1
  printf '%s' "$1" >/dev/tty
  read -r answer </dev/tty || return 1
  printf '%s' "$answer"
}

action=connect
assume_yes=0
selected_apps=""
bin_dir=""
named=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) assume_yes=1; shift ;;
    -y | --yes) assume_yes=1; shift ;;
    --list) action=list; shift ;;
    --remove) action=remove; shift ;;
    --print) action=print; shift ;;
    --apps) selected_apps="${2:?--apps needs a list}"; shift 2 ;;
    --bin-dir) bin_dir="${2:?--bin-dir needs a directory}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) printf 'Unknown option: %s (see gesher connect --help)\n' "$1" >&2; exit 64 ;;
    *)
      case " ${clients[*]} " in
        *" $1 "*) named+=("$1") ;;
        *) printf 'Unknown AI app: %s. Known: %s\n' "$1" "${clients[*]}" >&2; exit 64 ;;
      esac
      shift ;;
  esac
done

if [[ -z "$bin_dir" ]]; then
  # PREFIX/lib/gesher/active/connect.sh -> PREFIX/bin; a source checkout uses ~/.local/bin.
  if [[ "$(basename -- "$here")" == active || "$(basename -- "$(dirname -- "$here")")" == releases ]]; then
    bin_dir="$(cd -P -- "${here}/../../.." 2>/dev/null && pwd)/bin"
    [[ "$(basename -- "$here")" == active ]] || bin_dir="$(cd -P -- "${here}/../../../.." && pwd)/bin"
  else
    bin_dir="${HOME}/.local/bin"
  fi
fi
bin_dir="${bin_dir%/}"

apps=()
if [[ -n "$selected_apps" ]]; then
  IFS=, read -r -a requested <<<"$selected_apps"
  for app in "${requested[@]}"; do
    case " ${all_apps[*]} " in
      *" ${app} "*) apps+=("$app") ;;
      *) printf 'Unknown Mac app: %s. Known: %s\n' "$app" "${all_apps[*]}" >&2; exit 64 ;;
    esac
  done
else
  apps=("${all_apps[@]}")
fi

if [[ "$action" == print ]]; then
  snippet mcpServers
  exit 0
fi

found=()
for client in "${clients[@]}"; do installed "$client" && found+=("$client"); done

if [[ "$action" == list ]]; then
  printf '%s%-18s %-10s %s%s\n' "$bold" "AI APP" FOUND "GESHER" "$reset"
  for client in "${clients[@]}"; do
    if installed "$client"; then
      state="$(status "$client")"
      case "$state" in
        none) state="${dim}not connected${reset}" ;;
        unparsable) state="${yellow}settings file can't be read as JSON; connect prints what to add${reset}" ;;
        *) state="${green}connected${reset} (${state//,/, })" ;;
      esac
      printf '%-18s %-10s %s\n' "$client" yes "$state"
    else
      printf '%s%-18s %-10s %s%s\n' "$dim" "$client" no - "$reset"
    fi
  done
  printf '\nConnect with: %sgesher connect --all%s, or name the AI apps: %sgesher connect cursor zed%s\n' "$cyan" "$reset" "$cyan" "$reset"
  exit 0
fi

targets=()
if [[ ${#named[@]} -gt 0 ]]; then
  targets=("${named[@]}")
elif [[ "$action" == remove ]]; then
  for client in ${found[@]+"${found[@]}"}; do targets+=("$client"); done
elif [[ ${#found[@]} -eq 0 ]]; then
  printf 'No AI apps found. For any MCP client, add this to its settings (%sgesher connect --print%s):\n\n' "$cyan" "$reset"
  snippet mcpServers
  exit 0
elif [[ "$assume_yes" == 1 ]]; then
  targets=("${found[@]}")
else
  printf '%sFound these AI apps on your Mac:%s\n' "$bold" "$reset"
  i=1
  for client in "${found[@]}"; do
    printf '  %s%d%s  %s\n' "$cyan" "$i" "$reset" "$(display_name "$client")"
    i=$((i + 1))
  done
  if ! reply="$(ask "Connect Gesher to all of them? [Y/n, or numbers like 1 3] ")"; then
    printf 'No terminal to ask in. Run %sgesher connect --all%s, or name the AI apps (see --help).\n' "$cyan" "$reset"
    exit 0
  fi
  case "$reply" in
    "" | y | Y | yes | YES) targets=("${found[@]}") ;;
    n | N | no | NO) printf 'Nothing changed. Connect later with: %sgesher connect%s\n' "$cyan" "$reset"; exit 0 ;;
    *)
      for number in $reply; do
        [[ "$number" =~ ^[0-9]+$ && "$number" -ge 1 && "$number" -le ${#found[@]} ]] \
          || { printf 'Not a number from the list: %s\n' "$number" >&2; exit 64; }
        targets+=("${found[$((number - 1))]}")
      done ;;
  esac
fi

failed=0
connected=0
for client in ${targets[@]+"${targets[@]}"}; do
  if [[ "$action" == remove ]]; then
    remove_one "$client" || failed=1
  else
    if ! installed "$client"; then skip "$(display_name "$client"): not found on this Mac"; continue; fi
    if connect_one "$client"; then connected=1; else failed=1; fi
  fi
done
if [[ "$action" == connect && "$connected" == 1 && "${GESHER_CONNECT_QUIET_NEXT:-0}" != 1 ]]; then
  printf '\nNext: %sgesher permissions%s lets macOS ask for access. Then restart your AI apps and try\n' "$cyan" "$reset"
  printf '%s"What'"'"'s on my calendar tomorrow?"%s\n' "$bold" "$reset"
fi
exit "$failed"
