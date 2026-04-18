#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="WebMux"
BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BUILD_DIR="$SCRIPT_DIR/.build"
INSTALL_DIR="/Applications"

# --- Helpers ---
info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }
fail()  { printf "\033[1;31m==>\033[0m %s\n" "$1" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  build       Build debug binary (default)
  release     Build optimized release binary
  run         Build and launch the app
  install     Build release and copy to /Applications
  clean       Remove build artifacts
  bundle      Build and create .app bundle (without installing)
EOF
    exit 0
}

# --- Commands ---
do_build() {
    local mode="${1:-debug}"
    info "Building ($mode)..."
    if [[ "$mode" == "release" ]]; then
        swift build -v -c release --package-path "$SCRIPT_DIR"
    else
        swift build -v --package-path "$SCRIPT_DIR"
    fi
    ok "Build complete"
}

do_bundle() {
    local mode="${1:-debug}"
    do_build "$mode"

    info "Creating app bundle..."
    rm -rf "$BUNDLE"
    mkdir -p "$BUNDLE/Contents/MacOS"

    local bin="$BUILD_DIR/arm64-apple-macosx/$mode/$APP_NAME"
    [[ -f "$bin" ]] || bin="$BUILD_DIR/$mode/$APP_NAME"
    [[ -f "$bin" ]] || fail "Binary not found after build"

    cp "$bin" "$BUNDLE/Contents/MacOS/$APP_NAME"

    # Copy icon if present
    mkdir -p "$BUNDLE/Contents/Resources"
    if [[ -f "$SCRIPT_DIR/AppIcon.icns" ]]; then
        cp "$SCRIPT_DIR/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
    fi

    cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WebMux</string>
    <key>CFBundleIdentifier</key>
    <string>com.webmux.app</string>
    <key>CFBundleName</key>
    <string>WebMux</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

    # Sign with stable identity to avoid keychain prompts on rebuild
    codesign --force --deep --sign "WebMux Dev" --entitlements "$SCRIPT_DIR/WebMux.entitlements" "$BUNDLE"

    ok "Bundle created at $BUNDLE"
}

do_run() {
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 0.5
    do_bundle debug
    info "Launching $APP_NAME..."
    open "$BUNDLE"
}

do_install() {
    do_bundle release
    info "Installing to $INSTALL_DIR..."
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$BUNDLE" "$INSTALL_DIR/$APP_NAME.app"
    ok "Installed to $INSTALL_DIR/$APP_NAME.app"
    open "$INSTALL_DIR/$APP_NAME.app"
}

do_clean() {
    info "Cleaning..."
    rm -rf "$BUILD_DIR" "$BUNDLE"
    ok "Clean complete"
}

# --- Main ---
case "${1:-build}" in
    build)   do_build debug ;;
    release) do_build release ;;
    run)     do_run ;;
    install) do_install ;;
    clean)   do_clean ;;
    bundle)  do_bundle debug ;;
    help|-h|--help) usage ;;
    *) fail "Unknown command: $1. Run with 'help' for usage." ;;
esac
