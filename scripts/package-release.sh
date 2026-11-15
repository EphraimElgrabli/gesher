#!/bin/bash
# Build a release and package it as dist/gesher-<version>-macos-arm64.tar.gz (+ .sha256).
#
#   scripts/package-release.sh [--skip-build] [--scratch-path DIR] [--out DIR]
#
# The archive holds bin/ (the 7 CLIs, stripped of debug symbols and ad-hoc signed, and `gesher`), the bundled installer and its
# helper scripts, plugins/, LICENSE and README.txt. The one-line installer downloads it and runs
# `install.sh --from bin`, which re-signs the CLIs with the local signing identity.
set -euo pipefail

apps=(notes reminders calendar contacts maps weather freeform)
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="${root}/dist"
build=1
scratch=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) build=0; shift ;;
    --scratch-path) scratch=(--scratch-path "${2:?--scratch-path needs a directory}"); shift 2 ;;
    --out) out="${2:?--out needs a directory}"; shift 2 ;;
    -h | --help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 64 ;;
  esac
done

cd "$root"
# Keep the build machine's paths out of the binaries (#file strings, debug info).
prefix_map=(-Xswiftc -file-prefix-map -Xswiftc "${root}=." -Xcc "-ffile-prefix-map=${root}=.")
version="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' core/Sources/GesherKit/Operations/Version.swift)"
[[ -n "$version" ]] || { printf 'Could not read the version from Version.swift\n' >&2; exit 1; }
if [[ "$build" == 1 ]]; then
  swift build -c release --force-resolved-versions ${scratch[@]+"${scratch[@]}"} "${prefix_map[@]}"
fi
build_dir="$(swift build -c release --show-bin-path ${scratch[@]+"${scratch[@]}"} "${prefix_map[@]}")"

name="gesher-${version}-macos-arm64"
stage="${out}/${name}"
mkdir -p "$out"
rm -rf "$stage" "${out}/${name}.tar.gz" "${out}/${name}.tar.gz.sha256"
mkdir -p "${stage}/bin"
for app in "${apps[@]}"; do
  cp "${build_dir}/${app}-cli" "${stage}/bin/"
  # The linker's debug map still names the build machine's object files; drop it (signing follows).
  strip -S "${stage}/bin/${app}-cli"
  app_version="$("${stage}/bin/${app}-cli" --version)"
  [[ "$app_version" == "$version" ]] || { printf '%s-cli reports %s, expected %s\n' "$app" "$app_version" "$version" >&2; exit 1; }
done
cp scripts/gesher "${stage}/bin/"
"${root}/scripts/sign.sh" "${stage}/bin" --identity - >/dev/null
cp scripts/install.sh scripts/sign.sh scripts/create-signing-identity.sh scripts/install-plugins.sh scripts/connect.sh "$stage/"
cp -R plugins "${stage}/plugins"
cp LICENSE "$stage/"
cat >"${stage}/README.txt" <<EOF
Gesher ${version}: command-line tools and MCP servers for your Mac's apps.

Install:  ./install.sh --from bin   (from this folder)
Docs:     https://github.com/EphraimElgrabli/gesher
License:  GPL-3.0 (see LICENSE)
EOF
git rev-parse --short HEAD >"${stage}/COMMIT" 2>/dev/null || echo unknown >"${stage}/COMMIT"
find "$stage" -name .DS_Store -delete

# Reproducible-ish: no macOS metadata files, owner-neutral entries.
(cd "$out" && COPYFILE_DISABLE=1 tar --uid 0 --gid 0 -czf "${name}.tar.gz" "$name")
(cd "$out" && shasum -a 256 "${name}.tar.gz" >"${name}.tar.gz.sha256")
printf 'Packaged %s\n' "${out}/${name}.tar.gz"
cat "${out}/${name}.tar.gz.sha256"
