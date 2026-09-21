#!/bin/sh
# Build the zcode-pet floating window app (single-file AppKit, no Xcode project needed).
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
if [ -x "$DIR/zcode-pet-bin" ] && [ "$1" != "-f" ]; then
  exit 0
fi
swiftc -O -swift-version 5 -o zcode-pet-bin main.swift
echo "zcode-pet-bin built"
