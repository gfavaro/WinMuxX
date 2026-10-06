#!/bin/bash
set -euo pipefail
umask 077
test -n "$SIGNING_P12"
test -n "$SIGNING_PASSWORD"
test -n "$SIGNING_IDENTITY"
keychain="$RUNNER_TEMP/winmuxx-signing.keychain-db"
archive="$RUNNER_TEMP/winmuxx-signing.p12"
password="$(openssl rand -hex 32)"
echo "::add-mask::$password"
printf '%s' "$SIGNING_P12" | base64 --decode > "$archive"
trap 'rm -f "$archive"' EXIT
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$archive" -k "$keychain" -P "$SIGNING_PASSWORD" -T /usr/bin/codesign
certificate="$RUNNER_TEMP/winmuxx-signing.cer"
security find-certificate -p -c 'WinMuxX Local Code Signing' "$keychain" > "$certificate"
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$certificate"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain"
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security find-identity -v -p codesigning "$keychain" | grep -F "$SIGNING_IDENTITY"
