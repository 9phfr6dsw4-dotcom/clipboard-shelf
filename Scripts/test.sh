#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"

xcrun swiftc \
  -warnings-as-errors \
  "$ROOT/Sources/ClipboardCore.swift" \
  "$ROOT/Tests/CoreTests.swift" \
  -o "$ROOT/.build/ClipboardShelfCoreTests"

"$ROOT/.build/ClipboardShelfCoreTests"
