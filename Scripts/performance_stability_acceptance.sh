#!/bin/zsh -l
set -eu

swift test --filter PerformanceStabilityAcceptanceTests
