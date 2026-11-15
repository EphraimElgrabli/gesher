#!/bin/bash
# Install the Gesher Codex plugins and register them in the personal Codex marketplace, then print
# the Claude Code commands (Claude Code installs the plugins from the GitHub marketplace itself).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-plugins.sh [options]        install or refresh the Codex plugins
       install-plugins.sh --uninstall      remove the Codex plugins this script installed

Options:
  --apps LIST            only these apps, e.g. weather,maps (default: all)
  --bin-dir DIR          where the <app>-cli commands live (default: ~/.local/bin)
  --plugins-dir DIR      plugin sources (default: found next to this script)
  --codex-home DIR       Codex home (default: $CODEX_HOME or ~/.codex)
  --marketplace FILE     personal marketplace (default: ~/.agents/plugins/marketplace.json)
  --marketplace-name N   name for a new marketplace file (default: gesher; an existing file keeps its name)
  --quiet                do not print the Claude Code instructions
  -h, --help             show this help

Each plugin is copied to <codex-home>/plugins/gesher-<app>, with ${HOME}/.local/bin in its
.mcp.json rewritten to the absolute --bin-dir (Codex does not expand variables). Replaced copies
and the previous marketplace file are kept under <codex-home>/plugins/.backups/. Other marketplace
entries are left untouched. Restart Codex afterwards.
EOF
}

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugins_root=""
for candidate in "${here}/plugins" "${here}/../plugins" "${here}/../current/plugins"; do
  if [[ -d "$candidate" ]]; then plugins_root="$(cd -- "$candidate" && pwd)" && break; fi
done
codex_home="${CODEX_HOME:-${HOME}/.codex}"
marketplace="${HOME}/.agents/plugins/marketplace.json"
marketplace_name=""
bin_dir="${HOME}/.local/bin"
selected=""
action=install
quiet=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apps) selected="${2:?--apps needs a list}"; shift 2 ;;
    --bin-dir) bin_dir="${2:?--bin-dir needs a directory}"; shift 2 ;;
    --plugins-dir) plugins_root="${2:?--plugins-dir needs a directory}"; shift 2 ;;
    --codex-home) codex_home="${2:?--codex-home needs a directory}"; shift 2 ;;
    --marketplace) marketplace="${2:?--marketplace needs a file}"; shift 2 ;;
    --marketplace-name) marketplace_name="${2:?--marketplace-name needs a name}"; shift 2 ;;
    --uninstall) action=uninstall; shift ;;
    --quiet) quiet=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 64 ;;
  esac
done
bin_dir="${bin_dir%/}"

# Names of the gesher-* entries in the marketplace, with their indexes.
marketplace_index() {
  local count i
  count="$(plutil -extract plugins raw -o - "$marketplace" 2>/dev/null || echo 0)"
  for ((i = 0; i < count; i++)); do
    if [[ "$(plutil -extract "plugins.${i}.name" raw -o - "$marketplace" 2>/dev/null)" == "$1" ]]; then
      printf '%s\n' "$i"
      return
    fi
  done
}

selected_app() { [[ -z "$selected" || ",${selected}," == *",${1#gesher-},"* || ",${selected}," == *",${1},"* ]]; }

if [[ "$action" == uninstall ]]; then
  # Only plugins that launch commands from --bin-dir (i.e. that this install wrote) are removed.
  removed=()
  for dir in "${codex_home}/plugins"/gesher-*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    selected_app "$name" || continue
    grep -F "\"${bin_dir}/" "${dir}.mcp.json" >/dev/null 2>&1 || continue
    rm -rf "$dir"
    removed+=("$name")
  done
  if [[ ${#removed[@]} -gt 0 && -f "$marketplace" ]]; then
    name_in_file="$(plutil -extract name raw -o - "$marketplace" 2>/dev/null || true)"
    for name in "${removed[@]}"; do
      index="$(marketplace_index "$name")"
      [[ -n "$index" ]] && plutil -remove "plugins.${index}" "$marketplace"
      if command -v codex >/dev/null 2>&1 && [[ -n "$name_in_file" ]]; then
        codex plugin remove "${name}@${name_in_file}" >/dev/null 2>&1 || true
      fi
    done
    plutil -convert json -r "$marketplace"
    # A marketplace file this script created and that is now empty goes too.
    if [[ "$name_in_file" == gesher && "$(plutil -extract plugins raw -o - "$marketplace")" == 0 ]]; then
      rm -f "$marketplace"
    fi
  fi
  if [[ ${#removed[@]} -gt 0 ]]; then
    for name in "${removed[@]}"; do rm -rf "${codex_home}/plugins/.backups/${name}-"*; done
    rmdir "${codex_home}/plugins/cache/gesher" 2>/dev/null || true
  fi
  printf 'Removed %d Codex plugins from %s/plugins.\n' "${#removed[@]}" "$codex_home"
  exit 0
fi

[[ -n "$plugins_root" && -d "$plugins_root" ]] || { printf 'No plugins directory found; pass --plugins-dir.\n' >&2; exit 1; }
plugins=()
for dir in "$plugins_root"/gesher-*/; do
  name="$(basename "$dir")"
  selected_app "$name" || continue
  [[ -f "${dir}.codex-plugin/plugin.json" && -f "${dir}.mcp.json" ]] || { printf 'Invalid plugin: %s\n' "$dir" >&2; exit 1; }
  for file in "${dir}.codex-plugin/plugin.json" "${dir}.mcp.json"; do
    plutil -convert xml1 -o /dev/null "$file" || { printf 'Invalid JSON: %s\n' "$file" >&2; exit 1; }
  done
  plugins+=("$name")
done
[[ ${#plugins[@]} -gt 0 ]] || { printf 'No plugins selected.\n' >&2; exit 64; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backups="${codex_home}/plugins/.backups"
mkdir -p "${codex_home}/plugins" "$(dirname "$marketplace")"

if [[ ! -f "$marketplace" ]]; then
  marketplace_name="${marketplace_name:-gesher}"
  printf '{"name":"%s","interface":{"displayName":"%s"},"plugins":[]}\n' "$marketplace_name" "$marketplace_name" >"$marketplace"
else
  mkdir -p "$backups"
  cp -p "$marketplace" "${backups}/marketplace-${stamp}.json"
  # `codex plugin add NAME@MARKETPLACE` needs the name stored in the file.
  marketplace_name="$(plutil -extract name raw -o - "$marketplace")"
fi

# Marketplace paths are relative to the directory that contains .agents/ (normally $HOME).
market_root="$(cd -- "$(dirname -- "$marketplace")/../.." && pwd -P)"
plugins_dir="$(cd -- "${codex_home}/plugins" && pwd -P)"

for name in "${plugins[@]}"; do
  destination="${codex_home}/plugins/${name}"
  if [[ -e "$destination" ]]; then
    mkdir -p "$backups"
    mv "$destination" "${backups}/${name}-${stamp}"
  fi
  cp -R "${plugins_root}/${name}" "$destination"
  chmod -R u+w "$destination" # sources inside an installed release are read-only
  # Codex copies plugins into its cache verbatim and does not expand ${HOME}.
  sed -i '' "s|\${HOME}/.local/bin|${bin_dir}|g; s|\${HOME}|${HOME}|g" "${destination}/.mcp.json"

  if [[ "${plugins_dir}/" == "${market_root}/"* ]]; then
    path="./${plugins_dir#"${market_root}/"}/${name}"
  else
    path="${plugins_dir}/${name}"
  fi
  index="$(marketplace_index "$name")"
  if [[ -n "$index" ]]; then
    plutil -replace "plugins.${index}.source" -json "{\"source\":\"local\",\"path\":\"${path}\"}" "$marketplace"
  else
    count="$(plutil -extract plugins raw -o - "$marketplace")"
    plutil -insert "plugins.${count}" -json "{\"name\":\"${name}\",\"source\":{\"source\":\"local\",\"path\":\"${path}\"},\"policy\":{\"installation\":\"AVAILABLE\",\"authentication\":\"ON_USE\"},\"category\":\"Productivity\"}" "$marketplace"
  fi
  printf '  installed %s -> %s\n' "$name" "$destination"
done
plutil -convert json -r "$marketplace"
# Codex runs plugins from a versioned cache; `plugin add` refreshes it and enables the plugin.
if command -v codex >/dev/null 2>&1; then
  for name in "${plugins[@]}"; do
    codex plugin add "${name}@${marketplace_name}" >/dev/null || printf 'warning: codex plugin add %s@%s failed\n' "$name" "$marketplace_name" >&2
  done
fi
printf 'Codex marketplace "%s" updated (%s). Restart Codex to load the plugins.\n' "$marketplace_name" "$marketplace"
for name in "${plugins[@]}"; do
  app="${name#gesher-}"
  [[ -x "${bin_dir}/${app}-cli" ]] || printf 'note: %s/%s-cli is missing; install Gesher first\n' "$bin_dir" "$app"
done
if [[ "$quiet" == 0 ]]; then
  cat <<'EOF'

Claude Code:
  claude plugin marketplace add EphraimElgrabli/gesher
  claude plugin install gesher-reminders@gesher      (likewise gesher-calendar, -contacts, -notes,
                                                     -maps, -weather, -freeform)
EOF
fi
