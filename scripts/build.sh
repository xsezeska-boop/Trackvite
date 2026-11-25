#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcrun --find swift >/dev/null 2>&1; then
    echo "Install Xcode or the developer tools first: xcode-select --install" >&2
    exit 1
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="dist/Trackvite.app"
# Prefer a real, stable developer identity; never weaken the designated requirement.
SIGNING_IDENTITY="${TRACKVITE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:|"Developer ID Application:/ {print $2; exit}')"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="-"
    echo "No development certificate available. macOS permissions may need granting again after a rebuild." >&2
fi
# An ad-hoc replacement invalidates the user's TCC grants. Never do it silently.
if [[ "$SIGNING_IDENTITY" == "-" && -d "$APP" ]]; then
    if cmp -s "$BIN_DIR/Trackvite" "$APP/Contents/MacOS/Trackvite" && cmp -s Resources/Info.plist "$APP/Contents/Info.plist" && cmp -s Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; then
        codesign --verify --deep --strict "$APP"
        echo "Trackvite is already up to date. Existing signature and permissions preserved."
        exit 0
    fi
    if [[ "${TRACKVITE_REPLACE_ADHOC:-0}" != "1" ]]; then
        echo "Build compiled, but the installed app was not replaced: ad-hoc replacement breaks macOS permission grants." >&2
        echo "Use a development certificate with TRACKVITE_SIGNING_IDENTITY. For an intentional replacement and reauthorization, set TRACKVITE_REPLACE_ADHOC=1." >&2
        exit 2
    fi
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Trackvite" "$APP/Contents/MacOS/Trackvite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Recreate resource signing after adding or updating the icon.
rm -rf "$APP/Contents/_CodeSignature"
codesign --remove-signature "$APP/Contents/MacOS/Trackvite" 2>/dev/null || true
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP. Open the app in Finder."
