#!/bin/sh
# Removes Espanso Snippets Manager for the current user (macOS or Linux).
# Your Espanso snippets are never touched. Pass --remove-backups to also
# delete the backups the app made of your files.
set -eu

APP_ID="espanso-snippets-manager"
APP_NAME="Espanso Snippets"
REMOVE_BACKUPS=0
[ "${1:-}" = "--remove-backups" ] && REMOVE_BACKUPS=1

p=47811
while [ $p -lt 47821 ]; do
  if command -v curl >/dev/null 2>&1; then curl -fs -m 1 -X POST "http://127.0.0.1:$p/api/quit" >/dev/null 2>&1 || true; fi
  p=$((p + 1))
done

rm -f "$HOME/.local/bin/$APP_ID"
case "$(uname -s)" in
  Darwin)
    rm -rf "$HOME/Applications/$APP_NAME.app"
    BACKUPS="$HOME/Library/Application Support/Espanso Snippets Manager"
    ;;
  *)
    DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    rm -rf "${DATA:?}/$APP_ID"
    rm -f "$DATA/applications/$APP_ID.desktop"
    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true
    fi
    BACKUPS="${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID"
    ;;
esac

if [ "$REMOVE_BACKUPS" = 1 ]; then
  rm -rf "$BACKUPS"
elif [ -d "$BACKUPS" ]; then
  echo "Backups are still in $BACKUPS"
fi
echo "Espanso Snippets Manager was removed. Your Espanso snippets were not changed."
