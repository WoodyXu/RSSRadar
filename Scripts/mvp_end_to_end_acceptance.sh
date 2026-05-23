#!/bin/zsh
set -eu

mkdir -p .build/clang-module-cache .build/swiftpm-home
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-module-cache"

swift test --filter MVPEndToEndAcceptanceTests
