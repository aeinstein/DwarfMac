#!/usr/bin/env bash
# Baut und startet DwarfMac.
#
# VLCKit ist ein dynamisches Framework. `swift run` erzeugt kein .app-Bundle und
# bettet es daher nicht ein — der rpath sucht es unter
# `<bin>/../Frameworks/VLCKit.framework`. Dieses Skript verlinkt die macOS-Slice
# des heruntergeladenen xcframeworks dorthin, bevor es die App startet.
set -euo pipefail
cd "$(dirname "$0")"

swift build "$@"

BINPATH="$(swift build --show-bin-path "$@")"
DEST="$(dirname "$BINPATH")/Frameworks"
FW="$(find .build/artifacts -path '*macos-arm64*/VLCKit.framework' -type d 2>/dev/null | head -1)"

if [ -n "$FW" ]; then
  mkdir -p "$DEST"
  ln -sfn "$(pwd)/$FW" "$DEST/VLCKit.framework"
else
  echo "warning: VLCKit.framework nicht gefunden — 'swift package resolve' ausgeführt?" >&2
fi

exec swift run "$@" DwarfMac
