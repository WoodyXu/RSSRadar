.PHONY: build test lint verify

build:
	swift build

test:
	swift test

lint:
	Scripts/lint.sh

verify: lint test
