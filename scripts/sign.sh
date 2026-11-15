#!/bin/bash
# Sign the app executables in DIR (default: the release build directory) with a stable identity.
#
#   scripts/sign.sh [DIR] [--identity NAME_OR_SHA1]
#
# macOS keeps privacy grants (Calendar, Contacts, ...) per code identity. Each CLI gets the
# signing identifier io.github.ephraimelgrabli.gesher.<app> (its bundle id). The identity decides what survives a
# rebuild:
#   - a certificate identity: the designated requirement is "identifier + certificate", so grants
#     survive rebuilds and reinstalls. Used: --identity, else GESHER_SIGN_IDENTITY, else the
#     local "Gesher Local Signing" identity (scripts/create-signing-identity.sh) when present;
#   - ad-hoc (fallback, or --identity -): the requirement is the code hash, so every new build
#     needs new grants.
set -euo pipefail

apps=(notes reminders calendar contacts maps weather freeform)
dir=""
local_identity="Gesher Local Signing"
identity="${GESHER_SIGN_IDENTITY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) identity="${2:?--identity needs a name or SHA-1}"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) dir="$1"; shift ;;
  esac
done
if [[ -z "$identity" ]]; then
  identity="-"
  security find-identity -p codesigning 2>/dev/null | grep "\"${local_identity}\"" >/dev/null && identity="$local_identity"
fi
if [[ -z "$dir" ]]; then
  root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
  dir="$(cd "$root" && swift build -c release --show-bin-path)"
fi

for app in "${apps[@]}"; do
  binary="${dir}/${app}-cli"
  [[ -f "$binary" ]] || { printf 'Missing %s; build first.\n' "$binary" >&2; exit 1; }
  codesign --force --timestamp=none --sign "$identity" --identifier "io.github.ephraimelgrabli.gesher.${app}" "$binary" 2>/dev/null
done
if [[ "$identity" == "-" ]]; then
  printf 'Signed ad-hoc (io.github.ephraimelgrabli.gesher.<app>): privacy grants must be renewed after each new build.\n'
else
  printf 'Signed with a certificate identity: privacy grants survive rebuilds.\n'
fi
