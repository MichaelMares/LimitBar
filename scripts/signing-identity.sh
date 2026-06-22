#!/bin/zsh
# Ensure a STABLE self-signed code-signing identity exists, and print its name on stdout.
#
# Why: macOS Keychain "Always Allow" grants are pinned to an app's *designated requirement*,
# which for an ad-hoc signature is its one-off cdhash. Every rebuild changes that hash, so the
# grant stops matching and macOS re-prompts ("keychain access every few hours" during dev).
# Signing every build with the same self-signed certificate gives LimitBar a stable identity,
# so a single "Always Allow" survives rebuilds.
#
# Idempotent: creates the identity in the login keychain only if it's missing.
set -euo pipefail

IDENTITY="LimitBar Self-Signed"
# Throwaway password for the transient .p12 (Apple's importer rejects empty-password p12s).
P12PASS="limitbar"

# Already present? (No -v: a self-signed cert is usable for codesign even though it reports
# CSSMERR_TP_NOT_TRUSTED and is hidden from the "valid identities only" -v listing.)
if security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "$IDENTITY"
    exit 0
fi

echo "Creating self-signed code-signing identity \"$IDENTITY\"…" >&2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# OpenSSL config with the codeSigning extended key usage (required for a codesign identity).
cat > "$TMP/cfg" <<CFG
[ req ]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[ dn ]
CN = $IDENTITY
[ v3 ]
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
CFG

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" >/dev/null 2>&1

# -legacy: emit a PKCS#12 MAC that Apple's `security import` can verify (OpenSSL 3's modern
# default MAC is rejected with "MAC verification failed").
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$P12PASS" -name "$IDENTITY" >/dev/null 2>&1

LOGIN_KEYCHAIN="$(security login-keychain | tr -d ' "')"
# -T /usr/bin/codesign lets codesign use the private key without a per-build prompt.
security import "$TMP/id.p12" -k "$LOGIN_KEYCHAIN" -P "$P12PASS" \
    -T /usr/bin/codesign -A >/dev/null 2>&1

echo "Done. (You may be asked once to allow codesign to use the new key.)" >&2
echo "$IDENTITY"
