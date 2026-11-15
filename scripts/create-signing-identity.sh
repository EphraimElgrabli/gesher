#!/bin/bash
# Create a local, self-signed code-signing identity for Gesher in the login keychain.
#
#   scripts/create-signing-identity.sh [--name NAME]     (default name: Gesher Local Signing)
#
# macOS keeps privacy grants (Calendar, Contacts, Reminders, Full Disk Access) per executable path
# and code requirement. Ad-hoc signatures pin the requirement to the code hash, so every new build
# loses its grants. Signing with this certificate pins it to "identifier + this certificate"
# instead, so grants survive reinstalls. The certificate is only usable on this Mac: it is not
# trusted by anyone else, is not a Developer ID and does not notarize anything.
# Idempotent: an existing identity with the same name is reused. Remove it with Keychain Access.
set -euo pipefail

name="Gesher Local Signing"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="${2:?--name needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 64 ;;
  esac
done

keychain="${HOME}/Library/Keychains/login.keychain-db"
if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
  printf 'Signing identity already present: %s\n' "$name"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "${work}/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${name}
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -keyout "${work}/key.pem" -out "${work}/cert.pem" -config "${work}/cert.conf" 2>/dev/null
password="$(openssl rand -hex 16)"
# -legacy keeps the PKCS#12 readable by `security import` when openssl is OpenSSL 3.
openssl pkcs12 -export -legacy -inkey "${work}/key.pem" -in "${work}/cert.pem" -name "$name" \
  -out "${work}/identity.p12" -passout "pass:${password}" 2>/dev/null \
  || openssl pkcs12 -export -inkey "${work}/key.pem" -in "${work}/cert.pem" -name "$name" \
    -out "${work}/identity.p12" -passout "pass:${password}"
security import "${work}/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
printf 'Created signing identity "%s" in the login keychain.\n' "$name"
printf 'Install with it: scripts/install.sh (it is used automatically when present).\n'
