#!/bin/sh
# Packs dist/espanso-snippets-manager into the release archives.
set -eu
cd "$(dirname "$0")/../dist"
rm -f espanso-snippets-manager.zip espanso-snippets-manager.tar.gz
zip -qr -X espanso-snippets-manager.zip espanso-snippets-manager
tar -czf espanso-snippets-manager.tar.gz espanso-snippets-manager
for f in espanso-snippets-manager.zip espanso-snippets-manager.tar.gz; do
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi
done > SHA256SUMS.txt
cat SHA256SUMS.txt
