#!/bin/bash
# Gesher installer. Installs the CLIs as an immutable release and runs them from a stable path.
#
# Layout:  PREFIX/lib/gesher/releases/<version>-<time>-<commit>/   read-only executables + plugins
#          PREFIX/lib/gesher/{current,previous} -> releases/...
#          PREFIX/lib/gesher/active/   copies of `current`, replaced file by file (atomic mv)
#          PREFIX/bin/{gesher,<app>-cli} -> ../lib/gesher/active/...
# macOS records privacy grants per executable path and code signature. The CLIs always run from
# `active/` and are signed with a local certificate ("Gesher Local Signing", created on first
# install), so grants survive updates and rollbacks. Existing commands this installer does not own
# are never replaced. Nothing here needs sudo.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [options]              install or update Gesher
       install.sh --rollback             switch back to the previous release
       install.sh --uninstall            remove Gesher completely (keeps your config and grants)

Options:
  --prefix DIR           install under DIR (default: ~/.local)
  --from DIR             install the prebuilt executables in DIR instead of building
  --skip-build           source checkout: use the existing release build
  --sign-identity NAME   code-signing identity (default: "Gesher Local Signing", created if
                         missing; "-" signs ad-hoc, which loses privacy grants on every update)
  --no-plugins           do not refresh the Codex plugins, or disconnect AI apps on uninstall
  -h, --help             show this help

Without --from, install.sh must run from a source checkout (scripts/install.sh) and builds a
release with `swift build`. Connect AI apps afterwards with `gesher connect`.
EOF
}

apps=(notes reminders calendar contacts maps weather freeform)
commands=(gesher "${apps[@]/%/-cli}")
scripts=(install.sh sign.sh create-signing-identity.sh install-plugins.sh connect.sh)
local_identity="Gesher Local Signing"

if [[ -t 1 ]]; then
  bold=$'\033[1m' dim=$'\033[2m' green=$'\033[32m' yellow=$'\033[33m' red=$'\033[31m' reset=$'\033[0m'
else
  bold="" dim="" green="" yellow="" red="" reset=""
fi
step() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
ok() { printf '%s  ✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%swarning:%s %s\n' "$yellow" "$reset" "$*" >&2; }
die() {
  printf '%serror:%s %s\n' "$red" "$reset" "$1" >&2
  exit "${2:-1}"
}

lock() {
  mkdir -p "${managed}/releases"
  mkdir "${managed}/.install-lock" 2>/dev/null \
    || die "another install is running, or a stale lock remains: ${managed}/.install-lock"
  trap 'rm -rf "${managed}/.install-lock"; [[ -n "${staging:-}" ]] && { chmod -R u+w "$staging" 2>/dev/null; rm -rf "$staging"; }; true' EXIT
}

# Point a link at a target atomically (-h: never follow an existing directory symlink).
relink() {
  ln -sfn "$2" "${1}.next-$$"
  mv -fh "${1}.next-$$" "$1"
}

# Copy the files of the `current` release into active/ (same paths every time, atomic swaps).
activate() {
  local release file name
  release="${managed}/$(readlink "${managed}/current")"
  mkdir -p "${managed}/active"
  for file in "$release"/*; do
    [[ -f "$file" ]] || continue
    name="${file##*/}"
    cp -p "$file" "${managed}/active/.${name}.next-$$"
    mv -f "${managed}/active/.${name}.next-$$" "${managed}/active/${name}"
  done
}

link_commands() {
  local command link target existing
  mkdir -p "$bin"
  for command in "${commands[@]}"; do
    link="${bin}/${command}" target="../lib/gesher/active/${command}"
    existing="$(readlink "$link" 2>/dev/null || true)"
    if [[ "$existing" == "../lib/gesher/current/${command}" ]]; then
      relink "$link" "$target" # links from installers before active/
      continue
    fi
    if [[ -e "$link" || -L "$link" ]] && [[ "$existing" != "$target" ]]; then
      warn "skipped ${link}: an unrelated command already exists there"
      continue
    fi
    [[ -L "$link" ]] || ln -s "$target" "$link"
  done
}

has_identity() { security find-identity -p codesigning 2>/dev/null | grep -F "\"$1\"" >/dev/null; }

# The certificate identity keeps privacy grants across updates; create it on first install.
choose_identity() {
  [[ -n "$sign_identity" ]] && return
  if has_identity "$local_identity"; then
    sign_identity="$local_identity"
    return
  fi
  step "Creating the local code-signing identity \"${local_identity}\""
  printf '    %sKeeps macOS privacy grants across updates. macOS may ask for your login keychain password.%s\n' "$dim" "$reset"
  if "${here}/create-signing-identity.sh" --name "$local_identity" >/dev/null && has_identity "$local_identity"; then
    sign_identity="$local_identity"
    ok "signing identity created"
  else
    warn "could not create the signing identity; signing ad-hoc (privacy grants reset on every update)"
    sign_identity="-"
  fi
}

uninstall() {
  local command link removed=0
  step "Uninstalling Gesher from ${prefix}"
  for command in "${commands[@]}"; do
    link="${bin}/${command}"
    case "$(readlink "$link" 2>/dev/null || true)" in
      "../lib/gesher/active/${command}" | "../lib/gesher/current/${command}") rm -f "$link" && removed=$((removed + 1)) ;;
    esac
  done
  ok "removed ${removed} command links from ${bin}"
  if [[ "$plugins" == 1 && -x "${here}/connect.sh" ]]; then
    step "Disconnecting Gesher from your AI apps"
    "${here}/connect.sh" --remove --bin-dir "$bin" || warn "could not disconnect every AI app; see: gesher connect --list"
  elif [[ "$plugins" == 1 && -x "${here}/install-plugins.sh" ]]; then
    "${here}/install-plugins.sh" --uninstall --bin-dir "$bin" || warn "could not remove the Codex plugins"
  fi
  if [[ -d "$managed" ]]; then
    [[ -f "${managed}/.managed" || -d "${managed}/releases" ]] || die "${managed} does not look like a Gesher install; not removing it"
    chmod -R u+w "$managed"
    rm -rf "$managed"
    ok "removed ${managed}"
  fi
  rmdir "${prefix}/lib" "$bin" 2>/dev/null || true
  # The one-line installer tags the PATH line it adds to the shell profile with "# Gesher".
  local profile
  for profile in "${HOME}/.zshrc" "${HOME}/.bash_profile"; do
    if grep -qs ' # Gesher$' "$profile"; then
      # Drop the line and the blank line the installer put before it.
      awk '{ if (held) { if ($0 !~ / # Gesher$/) print prev; held = 0 }
             if ($0 == "") { held = 1; prev = $0; next }
             if ($0 !~ / # Gesher$/) print }
           END { if (held) print prev }' "$profile" >"${profile}.gesher-tmp" \
        && cat "${profile}.gesher-tmp" >"$profile" && rm -f "${profile}.gesher-tmp" \
        && ok "removed the PATH line from ${profile/#${HOME}/~}"
    fi
  done
  rm -f "${HOME}/.config/fish/conf.d/gesher.fish"
  printf '\nKept (delete by hand if you want them gone):\n'
  printf '  your settings and backups    rm -rf ~/.config/gesher\n'
  if security find-certificate -c "$local_identity" >/dev/null 2>&1; then
    printf '  the signing certificate      security delete-identity -c "%s" ~/Library/Keychains/login.keychain-db\n' "$local_identity"
  fi
  printf '  privacy grants               System Settings > Privacy & Security (remove the <app>-cli entries)\n'
  if command -v claude >/dev/null 2>&1 && claude plugin marketplace list 2>/dev/null | grep -qw gesher; then
    printf '  the Claude Code marketplace  claude plugin marketplace remove gesher\n'
  fi
}

rollback() {
  local previous current
  lock
  previous="$(readlink "${managed}/previous" || true)"
  current="$(readlink "${managed}/current" || true)"
  [[ -n "$previous" && -d "${managed}/${previous}" ]] || die "no previous release to roll back to"
  relink "${managed}/current" "$previous"
  [[ -n "$current" ]] && relink "${managed}/previous" "$current"
  activate
  link_commands
  ok "rolled back to ${previous#releases/}"
}

install() {
  local root="" source_dir plugins_src version="" app app_version commit name old count release keep
  if [[ -n "$from" ]]; then
    source_dir="$(cd -- "$from" && pwd)" || die "--from: no such directory: ${from}" 64
    commit="$(cat "${source_dir}/../COMMIT" 2>/dev/null || echo release)"
  else
    root="$(cd -- "${here}/.." && pwd)"
    [[ -f "${root}/Package.swift" ]] || die "not a source checkout; pass --from DIR with prebuilt executables (or use the one-line installer)" 64
    cd "$root"
    if [[ "$build" == 1 ]]; then
      step "Building a release (swift build -c release)"
      swift build -c release --force-resolved-versions
    fi
    source_dir="$(swift build -c release --show-bin-path)"
    commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    git diff --quiet HEAD 2>/dev/null || commit="${commit}-dirty"
  fi
  if [[ -d "${here}/plugins" ]]; then plugins_src="${here}/plugins"; else plugins_src="${here}/../plugins"; fi

  for app in "${apps[@]}"; do
    [[ -x "${source_dir}/${app}-cli" ]] || die "missing ${source_dir}/${app}-cli"
    app_version="$("${source_dir}/${app}-cli" --version)" || die "${app}-cli does not run on this Mac"
    [[ -z "$version" || "$version" == "$app_version" ]] || die "version mismatch: ${app}-cli is ${app_version}, expected ${version}"
    version="$app_version"
  done

  choose_identity
  lock
  name="${version}-$(date -u +%Y%m%dT%H%M%SZ)-${commit}"
  staging="${managed}/releases/.staging-${name}"
  rm -rf "$staging"
  mkdir -p "$staging"
  step "Installing Gesher ${version} into ${managed}"
  for app in "${apps[@]}"; do cp -p "${source_dir}/${app}-cli" "$staging/"; done
  if [[ -x "${source_dir}/gesher" ]]; then cp -p "${source_dir}/gesher" "$staging/"; else cp -p "${here}/gesher" "$staging/"; fi
  for script in "${scripts[@]}"; do cp -p "${here}/${script}" "$staging/"; done
  [[ -d "$plugins_src" ]] && cp -R "$plugins_src" "${staging}/plugins"
  "${staging}/sign.sh" "$staging" --identity "$sign_identity" >/dev/null
  if [[ "$sign_identity" == "-" ]]; then ok "signed ad-hoc"; else ok "signed with \"${sign_identity}\""; fi
  printf 'version=%s\ncommit=%s\n' "$version" "$commit" >"${staging}/RELEASE"
  for app in "${apps[@]}"; do "${staging}/${app}-cli" --version >/dev/null; done
  chmod -R a-w "$staging"
  mv "$staging" "${managed}/releases/${name}"
  staging=""

  old="$(readlink "${managed}/current" || true)"
  relink "${managed}/current" "releases/${name}"
  [[ -n "$old" && "$old" != "releases/${name}" ]] && relink "${managed}/previous" "$old"
  printf 'gesher-managed-v1\n' >"${managed}/.managed"
  activate
  link_commands
  ok "linked $((${#apps[@]} + 1)) commands into ${bin}"

  # Keep current, previous and the three newest other releases.
  keep=" releases/${name} ${old} "
  count=0
  # shellcheck disable=SC2010 # release names are generated: <version>-<time>-<commit>
  while IFS= read -r release; do
    [[ "$keep" == *" releases/${release} "* ]] && continue
    count=$((count + 1))
    if [[ $count -gt 3 ]]; then chmod -R u+w "${managed}/releases/${release}" && rm -rf "${managed}/releases/${release}"; fi
  done < <(ls -1t "${managed}/releases" | grep -v '^\.')

  # Codex runs copies of the plugins: refresh the ones a previous `gesher connect` installed.
  if [[ "$plugins" == 1 ]] && compgen -G "${CODEX_HOME:-${HOME}/.codex}/plugins/gesher-*" >/dev/null; then
    step "Refreshing the Codex plugins"
    "${managed}/active/install-plugins.sh" --bin-dir "$bin" --quiet >/dev/null || warn "Codex plugin refresh failed; retry with: gesher connect codex"
  fi
  ok "Gesher ${version} installed (${name})"
}

main() {
  prefix="${HOME}/.local"
  action=install
  build=1
  from=""
  plugins=1
  staging=""
  sign_identity="${GESHER_SIGN_IDENTITY:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
      --from) from="${2:?--from needs a directory}"; shift 2 ;;
      --skip-build) build=0; shift ;;
      --sign-identity) sign_identity="${2:?--sign-identity needs a name or SHA-1}"; shift 2 ;;
      --no-plugins) plugins=0; shift ;;
      --rollback) action=rollback; shift ;;
      --uninstall) action=uninstall; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" 64 ;;
    esac
  done
  [[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || die "Gesher needs macOS on Apple silicon (arm64)"
  mkdir -p "$prefix"
  prefix="$(cd -- "$prefix" && pwd)"
  here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  managed="${prefix}/lib/gesher"
  bin="${prefix}/bin"
  "$action"
}

main "$@"
