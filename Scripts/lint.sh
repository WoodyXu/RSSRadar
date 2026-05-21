#!/bin/sh

set -eu

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: SwiftLint is not installed. Install it with 'brew install swiftlint' or another local SwiftLint distribution." >&2
    exit 127
fi

mkdir -p .build/swiftlint-cache

swiftlint lint --config .swiftlint.yml --strict --cache-path .build/swiftlint-cache
