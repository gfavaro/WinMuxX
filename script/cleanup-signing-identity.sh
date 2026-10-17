#!/bin/bash
# A partially completed import must not prevent deletion of its private-key material.
set -uo pipefail
cleanup_status=0
certificate="$RUNNER_TEMP/winmuxx-signing.cer"
keychain="$RUNNER_TEMP/winmuxx-signing.keychain-db"

remove_security_item() {
    local output
    if output="$("$@" 2>&1)"; then
        return
    fi
    if [[ "$output" == *"could not be found"* ]]; then
        echo 'Signing item already absent; continuing cleanup.'
    else
        printf '::warning::Signing cleanup failed: %s\n' "$output" >&2
        cleanup_status=1
    fi
}

if test -f "$certificate"; then
    remove_security_item sudo -n security remove-trusted-cert -d "$certificate"
fi
if test -f "$keychain"; then
    remove_security_item security delete-keychain "$keychain"
fi
# Remove even when trust/keychain cleanup failed; retain the nonzero exit status.
rm -f "$certificate" "$RUNNER_TEMP/winmuxx-signing.p12" || cleanup_status=1
exit "$cleanup_status"
