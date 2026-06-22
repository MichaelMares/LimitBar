#!/bin/zsh
# Build LimitBar and wrap it into LimitBar.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/LimitBar.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/LimitBar" "$APP/Contents/MacOS/LimitBar"

# App icon. Regenerate from docs/icon.svg if it's newer (or missing).
if [[ ! -f "$ROOT/Resources/AppIcon.icns" || "$ROOT/docs/icon.svg" -nt "$ROOT/Resources/AppIcon.icns" ]]; then
    "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LimitBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.limitbar.LimitBar</string>
    <key>CFBundleName</key>
    <string>LimitBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Choose the signer: a stable self-signed identity (so the macOS Keychain "Always Allow" grant
# for the Claude credentials item survives rebuilds — ad-hoc "-" gets a new cdhash every build
# and re-prompts). Set LIMITBAR_ADHOC=1 to fall back to ad-hoc signing.
if [[ "${LIMITBAR_ADHOC:-0}" == "1" ]]; then
    SIGNER="-"
else
    SIGNER="$("$ROOT/scripts/signing-identity.sh")"
fi

# iCloud-synced folders keep re-adding com.apple.FinderInfo to the bundle, which makes codesign
# refuse ("resource fork ... not allowed"). Clear xattrs and sign, retrying to beat the race.
signed=0
for _ in 1 2 3 4 5; do
    xattr -cr "$APP" 2>/dev/null || true
    if codesign --force --sign "$SIGNER" "$APP" 2>/dev/null; then signed=1; break; fi
    sleep 1
done
if [[ "$signed" != "1" ]]; then
    echo "codesign failed after retries (extended-attribute race?)." >&2
    exit 1
fi
codesign --verify "$APP" 2>/dev/null && echo "Signed with: $SIGNER"
echo "Bundled: $APP"
