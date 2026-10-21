#!/bin/sh
# Installs Espanso Snippets Manager for the current user on macOS or Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/gilikarn/Espanso-Snippets-Manager/main/install/install.sh | sh
#
# Or run ./install.sh from an extracted release folder.
# Set ESM_VERSION=v1.2.3 to install a specific release instead of the latest.
set -eu

REPO="gilikarn/Espanso-Snippets-Manager"
VERSION="${ESM_VERSION:-latest}"
APP_ID="espanso-snippets-manager"
APP_NAME="Espanso Snippets"
FILES="index.html server.py install.sh uninstall.sh icon.svg icon.png LICENSE README.md VERSION"

say() { printf '  %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# 1. Find the files: next to this script, or download the release.
SRC=""
TMP=""
case "$0" in
  */install.sh|install.sh)
    here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
    if [ -f "$here/index.html" ] && [ -f "$here/server.py" ]; then SRC="$here"; fi ;;
esac
if [ -z "$SRC" ]; then
  if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/$REPO/releases/latest/download/$APP_ID.tar.gz"
  else
    URL="https://github.com/$REPO/releases/download/$VERSION/$APP_ID.tar.gz"
  fi
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  say "Downloading $URL"
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$URL" -o "$TMP/esm.tar.gz"
  elif command -v wget >/dev/null 2>&1; then wget -q "$URL" -O "$TMP/esm.tar.gz"
  else die "curl or wget is needed to download the app."; fi
  tar -xzf "$TMP/esm.tar.gz" -C "$TMP"
  SRC="$TMP/$APP_ID"
fi

echo "Installing Espanso Snippets Manager"

if ! command -v python3 >/dev/null 2>&1; then
  say "Note: Python 3 wasn't found. The app needs it to run."
  case "$(uname -s)" in
    Darwin) say "Install it with 'xcode-select --install' or from https://www.python.org/downloads/" ;;
    *)      say "Install it with your package manager, e.g. 'sudo apt install python3'" ;;
  esac
fi

# Ask a running copy to close so its files can be replaced.
p=47811
while [ $p -lt 47821 ]; do
  if command -v curl >/dev/null 2>&1; then curl -fs -m 1 -X POST "http://127.0.0.1:$p/api/quit" >/dev/null 2>&1 || true; fi
  p=$((p + 1))
done

copy_files() { # $1 = destination
  mkdir -p "$1"
  for f in $FILES; do
    if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$1/$f"; fi
  done
  chmod +x "$1/server.py" "$1/install.sh" "$1/uninstall.sh" 2>/dev/null || true
}

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

case "$(uname -s)" in
  Darwin)
    APP="$HOME/Applications/$APP_NAME.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    copy_files "$APP/Contents/Resources"
    cat > "$APP/Contents/MacOS/$APP_ID" <<'LAUNCHER'
#!/bin/sh
# Apps opened from Finder get a minimal PATH, so look for Python in the usual places.
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/../Resources" && pwd)
for PY in /opt/homebrew/bin/python3 /usr/local/bin/python3 /Library/Frameworks/Python.framework/Versions/Current/bin/python3 /usr/bin/python3; do
  if [ -x "$PY" ]; then exec "$PY" "$HERE/server.py" "$@"; fi
done
osascript -e 'display alert "Espanso Snippets needs Python 3" message "Install it from python.org or with xcode-select --install, then try again."'
exit 1
LAUNCHER
    chmod +x "$APP/Contents/MacOS/$APP_ID"
    if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
      SET="$(mktemp -d)/icon.iconset"
      mkdir -p "$SET"
      for s in 16 32 128 256 512; do
        sips -z $s $s "$SRC/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
        d=$((s * 2)); if [ $d -le 512 ]; then sips -z $d $d "$SRC/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true; fi
      done
      iconutil -c icns "$SET" -o "$APP/Contents/Resources/icon.icns" >/dev/null 2>&1 || true
    fi
    VER=$(cat "$SRC/VERSION" 2>/dev/null || echo 0.0.0)
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.espanso-snippets-manager</string>
  <key>CFBundleVersion</key><string>$VER</string>
  <key>CFBundleShortVersionString</key><string>$VER</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_ID</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$APP/Contents/MacOS/$APP_ID" > "$BIN_DIR/$APP_ID"
    chmod +x "$BIN_DIR/$APP_ID"
    say "Installed $APP"
    echo ""
    echo "Done. Open '$APP_NAME' from your Applications folder (in your home folder) or Spotlight."
    ;;
  *)
    DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    DEST="$DATA/$APP_ID"
    copy_files "$DEST"
    cat > "$BIN_DIR/$APP_ID" <<LAUNCHER
#!/bin/sh
exec python3 "$DEST/server.py" "\$@"
LAUNCHER
    chmod +x "$BIN_DIR/$APP_ID"
    mkdir -p "$DATA/applications"
    cat > "$DATA/applications/$APP_ID.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Edit your Espanso snippets
Exec=$BIN_DIR/$APP_ID
Icon=$DEST/icon.png
Terminal=false
Categories=Utility;TextTools;
Keywords=espanso;snippets;text;expander;
DESKTOP
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true
    fi
    say "Installed to $DEST"
    say "Added launcher $BIN_DIR/$APP_ID and a menu entry"
    echo ""
    echo "Done. Open '$APP_NAME' from your app menu, or run: $APP_ID"
    ;;
esac

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Tip: add $BIN_DIR to your PATH to run '$APP_ID' from a terminal." ;;
esac
