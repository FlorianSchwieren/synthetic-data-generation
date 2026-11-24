#!/bin/bash
# Build the zip that claude.ai accepts as a skill upload: dist/synthetic-data-generation.zip
set -euo pipefail
cd "$(dirname "$0")/.."
name=synthetic-data-generation
mkdir -p dist
rm -f "dist/$name.zip"
(cd skills && zip -qr "../dist/$name.zip" "$name" -x '*.DS_Store')
unzip -l "dist/$name.zip"
