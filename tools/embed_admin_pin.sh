#!/bin/sh
# Xcode build phase: puts the SHA-256 of the admin PIN (never the PIN itself) into the built
# Info.plist as KTXAdminPinSHA256. The settings screen compares against it before the server
# address can be changed. Same PIN as the Android app.
#
# PIN source, first found wins (both outside git):
#   1. environment variable KTX_ADMIN_PIN (e.g. `KTX_ADMIN_PIN=... xcodebuild ...`)
#   2. Secrets.xcconfig at the repository root, line: KTX_ADMIN_PIN = <pin>
# Without one: 000000 with a warning (like Android); an Archive (ACTION=install) fails instead.
set -eu

pin="${KTX_ADMIN_PIN:-}"
secrets="${SRCROOT}/Secrets.xcconfig"
if [ -z "$pin" ] && [ -f "$secrets" ]; then
    pin=$(sed -n 's/^[[:space:]]*KTX_ADMIN_PIN[[:space:]]*=[[:space:]]*//p' "$secrets" | tail -n 1 | tr -d '[:space:]')
fi

if [ -z "$pin" ]; then
    if [ "${ACTION:-build}" = "install" ]; then
        echo "error: KTX_ADMIN_PIN not set (Secrets.xcconfig or environment); refusing to archive with the default PIN"
        exit 1
    fi
    echo "warning: KTX_ADMIN_PIN not set (Secrets.xcconfig or environment); using 000000"
    pin="000000"
fi

hash=$(printf '%s' "$pin" | shasum -a 256 | cut -d ' ' -f 1)
plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
/usr/libexec/PlistBuddy -c "Delete :KTXAdminPinSHA256" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :KTXAdminPinSHA256 string $hash" "$plist"
