#!/usr/bin/env bash
# Builds MarkdownQuickLook.app with both Quick Look extensions inside it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/MarkdownQuickLook.app"
BUNDLE_ID="${MDQL_BUNDLE_ID:-com.kimwickell.MarkdownQuickLook}"
VERSION="$(cat "$ROOT/VERSION")"
SDK="$(xcrun --show-sdk-path)"
DEPLOYMENT_TARGET="12.0"
SIGN_IDENTITY="${MDQL_SIGN_IDENTITY:--}"

CORE_SOURCES=("$ROOT"/Sources/MarkdownQuickLookCore/*.swift)

say() { printf '\033[1m%s\033[0m\n' "$*"; }

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/PlugIns"

fill_plist() {
    sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" -e "s|__VERSION__|$VERSION|g" "$1" > "$2"
}

compile() {
    local output="$1"; shift
    local -a entry=()
    if [[ "${1:-}" == "--extension" ]]; then
        shift
        # App extensions have no main(); Foundation supplies the entry point.
        entry=(-parse-as-library -Xlinker -e -Xlinker _NSExtensionMain)
    fi
    swiftc \
        -swift-version 5 \
        -target "arm64-apple-macosx$DEPLOYMENT_TARGET" \
        -sdk "$SDK" \
        -O -whole-module-optimization \
        ${entry[@]+"${entry[@]}"} \
        -o "$output" \
        "${CORE_SOURCES[@]}" "$@"
}

say "Building extensions"
for kind in Preview Thumbnail; do
    appex="$APP/Contents/PlugIns/Markdown$kind.appex"
    mkdir -p "$appex/Contents/MacOS" "$appex/Contents/Resources"
    fill_plist "$ROOT/Support/$kind-Info.plist" "$appex/Contents/Info.plist"
    compile "$appex/Contents/MacOS/Markdown$kind" --extension "$ROOT/Extensions/$kind"/*.swift
    cp -R "$ROOT/Resources/." "$appex/Contents/Resources/"
done

say "Building container app"
fill_plist "$ROOT/Support/App-Info.plist" "$APP/Contents/Info.plist"
compile "$APP/Contents/MacOS/MarkdownQuickLook" "$ROOT/App"/*.swift
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true

say "Signing"
# Nested code is signed first: signing the app seals whatever is inside it.
for appex in "$APP/Contents/PlugIns"/*.appex; do
    codesign --force --sign "$SIGN_IDENTITY" \
        --entitlements "$ROOT/Support/extension.entitlements" \
        --timestamp=none "$appex" >/dev/null
done
codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Support/app.entitlements" \
    --timestamp=none "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

say "Built $APP ($(du -sh "$APP" | cut -f1))"
