# Repository Guidelines

## Project Structure & Module Organization

This repository currently contains planning docs:

- `memory-bank/design-document.md` describes the RSSRadar MVP experience, product constraints, and core objects.
- `memory-bank/tech-stack.md` recommends the implementation stack and target architecture.

The planned app is a native macOS Swift/SwiftUI application. When code is added, follow this documented structure:

```text
RSSRadar/
├── RSSRadarApp/                 # macOS app target: App, Views, ViewModels, Resources
├── Packages/                    # Internal Swift packages by domain
│   ├── RSSRadarCore/
│   ├── RSSRadarPersistence/
│   ├── RSSRadarFeeds/
│   ├── RSSRadarAI/
│   └── RSSRadarProcessing/
└── Tests/                       # XCTest or Swift Testing suites
```

Keep UI, persistence, AI provider code, feed parsing, and processing orchestration separated. UI should call view models or services, not SQLite or AI APIs.

## Build, Test, and Development Commands

No Xcode project or package manifest exists yet. Once implementation begins, prefer Swift Package Manager and Xcode commands:

- `swift build` builds Swift packages.
- `swift test` runs package tests.
- `xcodebuild -scheme RSSRadar -destination 'platform=macOS' test` runs app-target tests.

Document new setup, build, lint, or release commands here as they are introduced.

## Coding Style & Naming Conventions

Use Swift and SwiftUI conventions from the technical plan. Prefer `async/await`, `actor` isolation for shared mutable state, and `@MainActor` for UI-facing updates. Use four-space indentation.

Name types with `UpperCamelCase` (`TopicBrief`, `ProcessingEngine`) and functions, properties, and enum cases with `lowerCamelCase` (`fetchFeeds`, `articleAnalysis`). Align domain names with `design-document.md`: `Feed`, `Article`, `ArticleAnalysis`, `Topic`, and `TopicBrief`.

## Testing Guidelines

Use XCTest or Swift Testing. Place tests under `Tests/` with names that mirror the module or behavior, such as `FeedParserTests` or `ProcessingQueueRecoveryTests`.

Prioritize coverage for database migrations, RSS/OPML parsing, AI provider JSON validation, retries, and queue recovery. Use `URLProtocol` mocks or equivalent test doubles for network code.

## Commit & Pull Request Guidelines

This directory is not currently a git repository, so no local commit convention is available. Until one is established, use concise imperative messages:

- `Add RSS feed parser package`
- `Implement topic brief export`

Pull requests should include a short description, test evidence, linked issue or design section when relevant, and screenshots for UI changes. Call out local-data, Keychain, or AI-provider changes.

## Security & Configuration Tips

RSSRadar is local-first. Do not add developer-hosted servers, cloud sync, telemetry, or AI proxy behavior unless the product docs are updated first. Store API keys only in macOS Keychain, never in SQLite, logs, fixtures, or screenshots.

# 重要提示
- 写任何代码前必须完整阅读 memory-bank/@architecture.md
- 写任何代码前必须完整阅读 memory-bank/@design-document.md
- 每完成一个重大功能或里程碑后，必须更新 memory-bank/@architecture.md 和 memory-bank/@progress.md
- Use DESIGN.md as reference before you write any UI.