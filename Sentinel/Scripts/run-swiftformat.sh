#!/bin/sh

set -eu

PROJECT_ROOT="${SRCROOT:-$(pwd)}"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

SWIFTFORMAT_BIN="$(command -v swiftformat || true)"

if [ -n "${SWIFTFORMAT_BIN}" ]; then
    echo "SwiftFormat: formatting sources (format-fix)…"
    "${SWIFTFORMAT_BIN}" \
        "${PROJECT_ROOT}/Sentinel" \
        "${PROJECT_ROOT}/SentinelTests" \
        "${PROJECT_ROOT}/SentinelUITests" \
        --config "${PROJECT_ROOT}/.swiftformat"
else
    echo "warning: SwiftFormat is not installed or not visible to Xcode. Install it with: brew install swiftformat"
fi
