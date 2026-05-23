.PHONY: build test lint privacy-audit performance-stability mvp-e2e verify

build:
	swift build

test:
	swift test

lint:
	Scripts/lint.sh

privacy-audit:
	Scripts/privacy_security_audit.sh

performance-stability:
	Scripts/performance_stability_acceptance.sh

mvp-e2e:
	Scripts/mvp_end_to_end_acceptance.sh

verify: lint privacy-audit test
