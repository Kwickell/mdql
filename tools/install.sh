#!/usr/bin/env bash
# Installs the built app into /Applications and registers its extensions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MarkdownQuickLook.app"
SOURCE="$ROOT/build/$APP_NAME"
DESTINATION="${MDQL_INSTALL_DIR:-/Applications}/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

say() { printf '\033[1m%s\033[0m\n' "$*"; }

if [[ "${1:-}" == "--uninstall" ]]; then
    say "Removing $DESTINATION"
    for appex in "$DESTINATION"/Contents/PlugIns/*.appex; do
        [[ -e "$appex" ]] && pluginkit -r "$appex" 2>/dev/null || true
    done
    "$LSREGISTER" -u "$DESTINATION" 2>/dev/null || true
    rm -rf "$DESTINATION"
    qlmanage -r >/dev/null 2>&1 || true
    say "Removed."
    exit 0
fi

[[ -d "$SOURCE" ]] || { echo "build first: make build" >&2; exit 1; }

say "Installing to $DESTINATION"
rm -rf "$DESTINATION"
cp -R "$SOURCE" "$DESTINATION"

say "Registering"
"$LSREGISTER" -f "$DESTINATION"
for appex in "$DESTINATION"/Contents/PlugIns/*.appex; do
    pluginkit -a "$appex" 2>/dev/null || true
done
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall -9 QuickLookUIService 2>/dev/null || true

say "Registered extensions"
pluginkit -m -p com.apple.quicklook.preview -vvv 2>/dev/null | grep -i markdown || echo "  (preview extension not listed yet)"
pluginkit -m -p com.apple.quicklook.thumbnail -vvv 2>/dev/null | grep -i markdown || echo "  (thumbnail extension not listed yet)"
