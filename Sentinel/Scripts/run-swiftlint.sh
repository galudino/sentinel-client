#!/bin/sh

set -eu

PROJECT_ROOT="${SRCROOT:-$(pwd)}"
export TMPDIR="/tmp/"
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

SWIFTLINT_BIN="$(command -v swiftlint || true)"

if [ -n "${SWIFTLINT_BIN}" ]; then
    "${SWIFTLINT_BIN}" lint \
        --config "${PROJECT_ROOT}/.swiftlint.yml" \
        --working-directory "${PROJECT_ROOT}"
else
    echo "warning: SwiftLint is not installed or not visible to Xcode. Install it with: brew install swiftlint"
fi
