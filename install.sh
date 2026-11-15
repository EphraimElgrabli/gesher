#!/bin/bash
# Gesher one-line installer: https://github.com/EphraimElgrabli/gesher
#
#   curl -fsSL https://raw.githubusercontent.com/EphraimElgrabli/gesher/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --version 1.0.0 --prefix ~/.local --no-connect
#
# Downloads a release archive from GitHub, verifies its SHA-256 checksum and runs the installer
# inside it. Installs into ~/.local (no sudo), adds its bin/ to the PATH in your shell profile, and
# offers to connect the AI apps it finds (`gesher connect`). Everything runs inside main(), called
# on the last line, so a partially downloaded script does nothing.
set -euo pipefail

repo="EphraimElgrabli/gesher"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --version X.Y.Z   install this release (default: the latest)
  --prefix DIR      install under DIR (default: ~/.local)
  --connect         connect every AI app found, without asking
  --no-connect      don't connect any AI app (do it later with: gesher connect)
  --no-modify-path  don't add the install's bin/ to the PATH in ~/.zshrc or ~/.bash_profile
  --archive FILE    install from a local gesher-*.tar.gz (checked against FILE.sha256 if present)
  -h, --help        show this help

Environment: GESHER_SIGN_IDENTITY="-" signs ad-hoc instead of with a local certificate.
EOF
}

main() {
  local version="" prefix="${HOME}/.local" archive="" work major connect=ask modify_path=1 plugins=()
  if [[ -t 1 ]]; then
    bold=$'\033[1m' dim=$'\033[2m' red=$'\033[31m' yellow=$'\033[33m' cyan=$'\033[36m' reset=$'\033[0m'
  else
    bold="" dim="" red="" yellow="" cyan="" reset=""
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) version="${2:?--version needs a value, e.g. 1.0.0}"; version="${version#v}"; shift 2 ;;
      --prefix) prefix="${2:?--prefix needs a directory}"; shift 2 ;;
      --connect) connect=all; shift ;;
      --no-connect) connect=none; shift ;;
      --no-plugins) connect=none; plugins=(--no-plugins); shift ;;
      --no-modify-path) modify_path=0; shift ;;
      --archive) archive="${2:?--archive needs a file}"; shift 2 ;;
      -h | --help) usage; return 0 ;;
      *) fail "unknown option: $1 (see --help)" ;;
    esac
  done

  printf '\n%sGesher%s %s- your Mac’s apps, for AI agents%s\n\n' "$bold" "$reset" "$dim" "$reset"

  [[ "$(uname -s)" == Darwin ]] || fail "Gesher runs on macOS only."
  [[ "$(uname -m)" == arm64 ]] || fail "Gesher needs an Apple silicon Mac (arm64); Intel Macs are not supported."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [[ "$major" -ge 26 ]] || fail "Gesher needs macOS 26 or later; this is macOS $(sw_vers -productVersion)."
  if [[ "$major" -lt 27 ]]; then
    warn "Gesher is only tested on macOS 27; this is macOS $(sw_vers -productVersion). Continuing."
  fi

  work="$(mktemp -d "${TMPDIR:-/tmp}/gesher-install.XXXXXX")"
  # shellcheck disable=SC2064 # expand $work now
  trap "rm -rf '${work}'" EXIT

  if [[ -n "$archive" ]]; then
    [[ -f "$archive" ]] || fail "no such archive: ${archive}"
    step "Using ${archive}"
    if [[ -f "${archive}.sha256" ]]; then
      verify "$archive" "${archive}.sha256"
    else
      printf '    %sno %s.sha256 next to it; skipping the checksum%s\n' "$dim" "${archive##*/}" "$reset"
    fi
  else
    command -v curl >/dev/null || fail "curl is required."
    if [[ -z "$version" ]]; then
      step "Finding the latest release"
      version="$(latest_version)" || fail "could not find the latest release of ${repo} (pass --version X.Y.Z)."
    fi
    local name="gesher-${version}-macos-arm64.tar.gz"
    local base="https://github.com/${repo}/releases/download/v${version}"
    step "Downloading Gesher ${version}"
    curl -fsSL --retry 3 -o "${work}/${name}" "${base}/${name}" || fail "download failed: ${base}/${name}"
    curl -fsSL --retry 3 -o "${work}/${name}.sha256" "${base}/${name}.sha256" || fail "checksum download failed: ${base}/${name}.sha256"
    archive="${work}/${name}"
    verify "$archive" "${archive}.sha256"
  fi

  mkdir -p "${work}/archive"
  tar -xzf "$archive" -C "${work}/archive" || fail "could not extract ${archive}"
  local root
  root="$(find "${work}/archive" -mindepth 2 -maxdepth 2 -name install.sh -type f | head -n 1)"
  [[ -n "$root" ]] || fail "the archive has no installer"
  root="$(dirname "$root")"
  [[ -d "${root}/bin" ]] || fail "the archive has no bin/ directory"

  "${root}/install.sh" --from "${root}/bin" --prefix "$prefix" ${plugins[@]+"${plugins[@]}"}

  prefix="$(cd -- "$prefix" && pwd)"
  [[ "$modify_path" == 1 ]] && add_to_path "${prefix}/bin"
  connect_apps "$prefix" "$connect"
  next_steps "$prefix"
}

step() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
warn() { printf '%swarning:%s %s\n' "$yellow" "$reset" "$*" >&2; }
fail() {
  printf '%serror:%s %s\n' "$red" "$reset" "$*" >&2
  exit 1
}

latest_version() {
  # The /releases/latest page redirects to /releases/tag/vX.Y.Z (no API rate limit).
  local url
  url="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")" || return 1
  [[ "$url" == */releases/tag/v* ]] || return 1
  printf '%s\n' "${url##*/releases/tag/v}"
}

# Check FILE against the "<sha256>  <name>" line in SUMS (the name in SUMS is ignored).
verify() {
  local expected
  expected="$(awk '{ print $1; exit }' "$2")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "malformed checksum file: $2"
  printf '%s  %s\n' "$expected" "$1" | shasum -a 256 -c - >/dev/null 2>&1 \
    || fail "checksum mismatch for ${1##*/}; the download is corrupt or was tampered with."
  printf '    checksum ok\n'
}

# Add BIN to the PATH for new shells (zsh, the macOS default, and bash), once.
add_to_path() {
  local bin="$1" profile line display="$1"
  case ":${PATH}:" in *":${bin}:"*) return ;; esac
  [[ "$display" == "${HOME}/"* ]] && display="\$HOME/${display#"${HOME}/"}"
  line="export PATH=\"${display}:\$PATH\" # Gesher"
  case "${SHELL:-/bin/zsh}" in
    */bash) profile="${HOME}/.bash_profile" ;;
    */fish)
      profile="${HOME}/.config/fish/conf.d/gesher.fish"
      line="fish_add_path --global \"${bin}\" # Gesher"
      mkdir -p "$(dirname "$profile")" ;;
    *) profile="${HOME}/.zshrc" ;;
  esac
  if ! grep -qsF "$line" "$profile"; then
    printf '\n%s\n' "$line" >>"$profile"
    printf '    added %s to your PATH in %s\n' "$display" "${profile/#${HOME}/~}"
  fi
  path_note=1
}

# Sets `connect` (a local of main) to "later" when there is no terminal to ask in.
connect_apps() {
  local script="${1}/lib/gesher/active/connect.sh"
  [[ -x "$script" ]] || return 0
  case "$2" in
    none) return 0 ;;
    all) printf '\n'; GESHER_CONNECT_QUIET_NEXT=1 "$script" --all --bin-dir "${1}/bin" || true ;;
    *)
      # Under `curl | bash` stdin is the script, so ask on the terminal itself.
      if [[ -r /dev/tty ]] && (: </dev/tty) 2>/dev/null; then
        printf '\n'
        GESHER_CONNECT_QUIET_NEXT=1 "$script" --bin-dir "${1}/bin" || true
      else
        connect=later
      fi ;;
  esac
}

next_steps() {
  local gesher=gesher
  # Until a new Terminal window picks up the PATH change, spell out the full path.
  if [[ "${path_note:-0}" == 1 ]]; then
    gesher="${1}/bin/gesher"
    [[ "$gesher" == "${HOME}/"* ]] && gesher="~/${gesher#"${HOME}/"}"
  fi
  printf '\n%s🌉 Gesher is installed.%s\n\n' "$bold" "$reset"
  if [[ "${connect:-}" == later ]]; then
    printf '  Connect your AI apps:     %s%s connect%s\n' "$cyan" "$gesher" "$reset"
  fi
  printf '  Let macOS ask for access: %s%s permissions%s\n' "$cyan" "$gesher" "$reset"
  printf '  Check that all is well:   %s%s doctor%s\n' "$cyan" "$gesher" "$reset"
  printf '\n  Then ask your AI app something like %s"What'"'"'s on my calendar tomorrow?"%s\n\n' "$bold" "$reset"
}

main "$@"
