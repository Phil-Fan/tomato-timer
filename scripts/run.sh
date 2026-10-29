#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project TomatoTimer.xcodeproj \
  -scheme TomatoTimer \
  -configuration Debug \
  -derivedDataPath .build \
  build

open .build/Build/Products/Debug/TomatoTimer.app
