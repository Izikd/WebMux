#!/usr/bin/env bash
# Install an official WebMux release from GitHub.
#
#   ./install.sh               install the latest release
#   ./install.sh v0.3.0        install a specific release
#   ./install.sh --list        list available releases
#
# Also works without cloning:
#   curl -fsSL https://raw.githubusercontent.com/Izikd/WebMux/main/install.sh | bash
set -euo pipefail

REPO="Izikd/WebMux"
APP_NAME="WebMux"
DEST_DIR="/Applications"
LAUNCH=1
FORCE=0
VERSION=""

info()  { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m==>\033[0m %s\n" "$1" >&2; }
fail()  { printf "\033[1;31m==>\033[0m %s\n" "$1" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [version] [options]

Installs an official $APP_NAME release from https://github.com/$REPO/releases.

Arguments:
  version        Release tag to install, e.g. v0.3.0 (default: latest)

Options:
  --list         List available releases and exit
  --dest DIR     Install into DIR instead of $DEST_DIR
  --no-launch    Don't open the app after installing
  --force        Reinstall even if that version is already installed
  -h, --help     Show this help
EOF
    exit 0
}

# --- GitHub API ---
api() {
    local auth=() body status
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    body="$(mktemp)"
    status="$(curl -sSL -o "$body" -w "%{http_code}" -H "Accept: application/vnd.github+json" \
        ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$REPO/$1")" \
        || { rm -f "$body"; fail "Couldn't reach GitHub. Check your internet connection."; }
    case "$status" in
        200) cat "$body"; rm -f "$body" ;;
        404) rm -f "$body"; fail "Not found on GitHub: ${2:-repos/$REPO/$1}. Run with --list to see available releases." ;;
        403|429) rm -f "$body"; fail "GitHub rate limit reached. Try again later, or set GITHUB_TOKEN." ;;
        *) rm -f "$body"; fail "GitHub API returned HTTP $status for repos/$REPO/$1." ;;
    esac
}

# Extracts all values of a string field from JSON (good enough for GitHub's flat fields).
json_field() { grep -o "\"$1\": *\"[^\"]*\"" | sed -E "s/\"$1\": *\"([^\"]*)\"/\1/"; }

list_releases() {
    info "Releases of $REPO:"
    api "releases?per_page=30" | json_field tag_name | sed 's/^/    /'
    exit 0
}

# --- Arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) list_releases ;;
        --dest) [[ $# -ge 2 ]] || fail "--dest needs a directory"; DEST_DIR="$2"; shift ;;
        --no-launch) LAUNCH=0 ;;
        --force) FORCE=1 ;;
        -h|--help) usage ;;
        -*) fail "Unknown option: $1 (see --help)" ;;
        *) [[ -z "$VERSION" ]] || fail "Only one version can be given"; VERSION="$1" ;;
    esac
    shift
done

[[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME is a macOS app."
mkdir -p "$DEST_DIR" 2>/dev/null || true
[[ -d "$DEST_DIR" ]] || fail "Install folder doesn't exist: $DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd -P)"  # real path, to match the running app's path
TARGET="$DEST_DIR/$APP_NAME.app"

# --- Resolve the release ---
if [[ -z "$VERSION" ]]; then
    info "Looking up the latest release..."
    release_json="$(api releases/latest)"
else
    [[ "$VERSION" == v* ]] || VERSION="v$VERSION"
    info "Looking up release $VERSION..."
    release_json="$(api "releases/tags/$VERSION" "release $VERSION")"
fi
tag="$(json_field tag_name <<< "$release_json" | head -1)"
zip_url="$(json_field browser_download_url <<< "$release_json" | grep -E "/$APP_NAME-[^/]*\.zip$" | head -1 || true)"
[[ -n "$tag" ]] || fail "Couldn't read the release from GitHub's response."
[[ -n "$zip_url" ]] || fail "Release $tag has no $APP_NAME-*.zip asset."

# --- Skip if already installed ---
installed=""
if [[ -f "$TARGET/Contents/Info.plist" ]]; then
    installed="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ "$FORCE" -eq 0 && "$installed" == "${tag#v}" ]]; then
    ok "$APP_NAME $tag is already installed at $TARGET (use --force to reinstall)."
    exit 0
fi
[[ -n "$installed" ]] && info "Installed version: $installed"

# --- Download and unpack ---
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

info "Downloading $tag..."
curl -fL --progress-bar -o "$work/release.zip" "$zip_url" || fail "Download failed: $zip_url"
ditto -x -k "$work/release.zip" "$work/unpacked" || fail "Couldn't unpack the release zip."

new_app="$work/unpacked/$APP_NAME.app"
[[ -x "$new_app/Contents/MacOS/$APP_NAME" ]] || fail "The release zip doesn't contain $APP_NAME.app."
codesign --verify "$new_app" 2>/dev/null || fail "The downloaded app's code signature is invalid; not installing."

# The binary must run on this Mac.
archs="$(lipo -archs "$new_app/Contents/MacOS/$APP_NAME" 2>/dev/null || true)"
machine="$(uname -m)"
if [[ -n "$archs" && " $archs " != *" $machine "* ]]; then
    fail "This release is built for $archs, but this Mac is $machine."
fi

# --- Quit the copy we're about to replace (other copies, e.g. dev builds, keep running) ---
running_pattern="^$TARGET/Contents/MacOS/$APP_NAME"
if pgrep -fq "$running_pattern"; then
    info "Quitting $APP_NAME..."
    osascript -e "tell application \"$TARGET\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -fq "$running_pattern" || break; sleep 0.5; done
    if pgrep -fq "$running_pattern"; then
        warn "$APP_NAME didn't quit; stopping it."
        pkill -f "$running_pattern" || true
        sleep 1
    fi
fi

# --- Install, keeping the old copy until the new one is in place ---
[[ -w "$DEST_DIR" ]] || fail "No write permission for $DEST_DIR."
backup=""
if [[ -e "$TARGET" ]]; then
    backup="$work/previous-$APP_NAME.app"
    mv "$TARGET" "$backup"
fi
if ! ditto "$new_app" "$TARGET"; then
    rm -rf "$TARGET"
    [[ -n "$backup" ]] && mv "$backup" "$TARGET"
    fail "Copying to $TARGET failed; the previous version was restored."
fi

ok "Installed $APP_NAME $tag at $TARGET"
warn "Releases are ad-hoc signed: WhatsApp may ask for your keychain password once after updating."

if [[ "$LAUNCH" -eq 1 ]]; then
    open "$TARGET"
fi
