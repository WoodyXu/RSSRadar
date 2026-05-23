#!/bin/sh

set -eu

failures=0

report_failure() {
    failures=$((failures + 1))
    printf '%s\n' "privacy-audit: $1" >&2
}

check_no_matches() {
    description=$1
    pattern=$2
    shift 2

    if rg -n -i "$pattern" "$@" >/tmp/rssradar_privacy_audit_matches 2>/dev/null; then
        report_failure "$description"
        cat /tmp/rssradar_privacy_audit_matches >&2
    fi
}

telemetry_pattern='Firebase|Sentry|PostHog|Analytics|Telemetry|Mixpanel|Amplitude|Datadog|Bugsnag|Rollbar|Crashlytics|Segment'
secret_pattern='api[_ -]?key|authorization|bearer |x-api-key|sk-[A-Za-z0-9_-]{8,}'

check_no_matches \
    "unexpected telemetry or cloud logging dependency reference found in package manifests" \
    "$telemetry_pattern" \
    Package.swift Package.resolved

check_no_matches \
    "unexpected telemetry or analytics import found in source or tests" \
    "import ($telemetry_pattern)" \
    RSSRadarApp Packages Tests

if rg -n 'https?://[^") <]+' RSSRadarApp Packages Package.swift >/tmp/rssradar_privacy_audit_urls 2>/dev/null; then
    if awk '
        /https:\/\/api\.openai\.com\/v1/ { next }
        /https:\/\/api\.anthropic\.com/ { next }
        /https:\/\/example\.com/ { next }
        /https:\/\/github\.com\/groue\/GRDB\.swift\.git/ { next }
        /https:\/\/github\.com\/nmdias\/FeedKit\.git/ { next }
        /https:\/\/github\.com\/scinfu\/SwiftSoup\.git/ { next }
        { print }
    ' /tmp/rssradar_privacy_audit_urls >/tmp/rssradar_privacy_audit_unexpected_urls; then
        if [ -s /tmp/rssradar_privacy_audit_unexpected_urls ]; then
            report_failure "unexpected hard-coded network endpoint found"
            cat /tmp/rssradar_privacy_audit_unexpected_urls >&2
        fi
    fi
fi

fixture_files=$(find Tests -path '*/Fixtures/*' -type f)
if [ -n "$fixture_files" ]; then
    # shellcheck disable=SC2086
    check_no_matches \
        "test fixture contains API key or authorization-looking plaintext" \
        "$secret_pattern" \
        $fixture_files
fi

prompt_files=$(find Packages/RSSRadarAI/Sources/RSSRadarAI/Prompts -type f)
if [ -n "$prompt_files" ]; then
    # shellcheck disable=SC2086
    check_no_matches \
        "prompt resource contains API key or authorization-looking plaintext" \
        "$secret_pattern" \
        $prompt_files
fi

log_files=$(find . \
    \( -path './.build' -o -path './.swiftpm' -o -path './.git' \) -prune -o \
    -name '*.log' -type f -print)
if [ -n "$log_files" ]; then
    # shellcheck disable=SC2086
    check_no_matches \
        "repository log file contains API key or authorization-looking plaintext" \
        "$secret_pattern" \
        $log_files
fi

markdown_exports=$(find . \
    \( -path './.build' -o -path './.swiftpm' -o -path './.git' -o -path './memory-bank' \) -prune -o \
    -name '*.md' -type f -print)
if [ -n "$markdown_exports" ]; then
    # shellcheck disable=SC2086
    check_no_matches \
        "repository Markdown export-like file contains API key or authorization-looking plaintext" \
        'authorization|bearer |x-api-key|sk-[A-Za-z0-9_-]{8,}' \
        $markdown_exports
fi

database_files=$(find . \
    \( -path './.build' -o -path './.swiftpm' -o -path './.git' \) -prune -o \
    \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -type f -print)
for database_file in $database_files; do
    if strings "$database_file" | rg -n -i "$secret_pattern" >/tmp/rssradar_privacy_audit_db_matches; then
        report_failure "database file contains API key or authorization-looking plaintext: $database_file"
        cat /tmp/rssradar_privacy_audit_db_matches >&2
    fi
done

rm -f \
    /tmp/rssradar_privacy_audit_matches \
    /tmp/rssradar_privacy_audit_urls \
    /tmp/rssradar_privacy_audit_unexpected_urls \
    /tmp/rssradar_privacy_audit_db_matches

if [ "$failures" -ne 0 ]; then
    exit 1
fi

printf '%s\n' "privacy-audit: passed"
