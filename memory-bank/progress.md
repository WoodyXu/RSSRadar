# Progress

## 2026-05-29 - UI refinements and AI timeout default

Updated the current app UI and AI timeout defaults.

- Replaced topic-card importance display in `主题聚合` with related article counts from `topic_articles`.
- Added a `刷新状态` button next to `运行待处理任务` in `任务状态`; it reloads the latest queue/log/settings snapshot without running jobs.
- Changed default AI timeout values from 60 seconds to 120 seconds in Core settings, Settings UI state, and AI provider configuration defaults.
- Added the app logo image to the left of the top `RSS Radar` sidebar brand label.
- Updated architecture and product docs for the new UI/default behavior.

Verification:

- `swift build` passed.
- `swift test --filter DomainModelTests --filter RepositoryTests --filter AIProviderTests --filter TopicBriefGenerationUseCaseTests` passed with 44 tests and 0 failures.
- `make verify` passed: SwiftLint 0 violations across 108 files, privacy audit passed, and `swift test` passed with 160 tests and 0 failures.

## 2026-05-28 - Manual topic brief extraction in Topics

Updated the Topics tab so TopicBrief generation is explicit and active-topic only.

- Added an active-topic “一键萃取” action with the hint “点击总结主题动态。” in Topic Detail.
- Wired the action through `TopicsViewModel` to `TopicBriefGenerationUseCase.regenerate(..., briefType: .full)`, using the saved AI settings and Keychain API Key only after the user clicks.
- Removed automatic full TopicBrief queueing from `TopicAssignmentUseCase`.
- Kept `generate_topic_brief` jobs unsupported in `ProcessingEngineExecutor`, so pending legacy jobs do not call TopicBrief generation automatically.
- Hid 最近变化、时间线、关键证据 for candidate and ignored topics in Topic Detail.
- Removed the 情报类型 metadata from Topic Detail.
- Made related articles in Topic Detail open their article URL in the default browser.
- Updated processing and end-to-end tests to assert active-topic assignment no longer queues TopicBrief generation and manual regeneration still produces the full brief.

Verification:

- `swift build` passed.
- `swift test --filter TopicAssignmentUseCaseTests --filter TopicBriefGenerationUseCaseTests --filter MVPEndToEndAcceptanceTests` passed with 11 tests and 0 failures.

## 2026-05-28 - Entity and dimension anchored topic generation

Reworked topic generation toward reusable entity/dimension anchors instead of narrow one-article issue titles.

- Updated `ArticleAnalysisPrompt.md` so `entities` explicitly cover company, person, product, industry, asset, technology, policy, and event dimensions.
- Updated article `possible_topics` guidance to return a small subset of reusable entity/dimension anchors rather than copying all entities or producing narrow "entity + impact/change" topics.
- Updated `TopicAssignmentPrompt.md` so all dimensions are treated equally, new topic names prefer reusable entity/dimension names, existing topics are preferred, and one article may have up to three high-confidence topic assignments.
- Relaxed `TopicAssignmentService` local validation so industry, asset, and technology topics such as `AI`, `白酒`, `新能源车`, `比特币`, and `RAG` are allowed.
- Changed local validation to reject meaningless generic names such as `新闻`, `市场`, `公司`, `科技`, `业务`, `news`, `market`, `company`, `technology`, and `business`.
- Updated `TopicAssignmentUseCase` so AI-proposed new topics reuse existing active or candidate topics with the same normalized name before creating a new candidate.
- Added tests for allowed dimension topics, rejected meaningless topic names, and active-topic reuse when AI returns an equivalent new topic.
- Updated `memory-bank/design-document.md` and `memory-bank/architecture.md` to match the new entity/dimension anchored strategy.

Verification:

- `make verify` passed: SwiftLint 0 violations across 108 files, privacy audit passed, and `swift test` passed with 160 tests and 0 failures.

## 2026-05-27 - Candidate topic Track and Ignore controls

Added candidate topic management controls to the Topics page.

- Added `Track` and `Ignore` buttons to the Topic Detail header when the selected topic is a candidate.
- Wired the buttons through `TopicsViewModel` to `CandidateTopicManagementUseCase.trackCandidate` and `ignoreCandidate`.
- Refreshed the topic list and detail after status changes.
- Preserved the current selection in All view; in Candidate-filtered view, processed topics move out of the filtered list.
- Kept the actions local-only: they do not trigger AI calls, scans, TopicBrief generation, or direct SQLite access from SwiftUI.

Verification:

- `swift build` passed.

## 2026-05-27 - Today and Topics app UI data hookup

Connected the app shell's Today and Topics navigation items to local topic data.

- Replaced the Today and Topics placeholder branches in `AppRootView`.
- Added `TodayViewModel` and `TodayView` backed by `TodayPageDataSource`.
- Added `TopicsViewModel` and `TopicsView` backed by `TopicRepository.fetchAll()` plus `TopicDetailDataSource`.
- Added a reusable app-level `TopicDetailView` for cached brief sections, evidence, and related articles.
- Added topic status display helpers for UI labels.
- Kept the new UI read-only: it does not trigger scans, AI calls, TopicBrief generation, or direct SQLite access.

Verification:

- `swift build` passed.

## 2026-05-27 - AI JSON stability and diagnostics

Completed an AI processing reliability milestone focused on provider diagnostics and JSON output stability.

- Added JSON response format support to OpenAI-compatible/custom chat completions requests.
- Captured OpenAI-compatible `finish_reason` in provider responses.
- Added structured provider diagnostics for empty assistant content, including status, finish reason, and a bounded response preview.
- Added AI diagnostic fields to processing failure logs without storing API keys, full request bodies, or article text.
- Increased article analysis output budget to `8192` tokens.
- Added an article content budget before prompt rendering to reduce long-input truncation risk; the current budget is 100,000 characters.
- Tightened article analysis, topic assignment, topic brief, and candidate preview prompts to require raw JSON only and smaller bounded arrays.
- Removed an unused topic assignment variable that produced a Swift compiler warning.

Verification:

- `swift test --filter AIProviderTests --filter ArticleAnalysisServiceTests --filter ProcessingEngineTests` passed with 25 tests and 0 failures.
- `make verify` passed: SwiftLint 0 violations, privacy audit passed, and `swift test` passed with 158 tests and 0 failures.

## 2026-05-20 - Step 1: macOS SwiftUI project skeleton

Completed implementation-plan Step 1.

- Created a pure Swift Package manifest with macOS 14.0+ as the deployment target.
- Added the `RSSRadar` executable product backed by the `RSSRadarApp` SwiftUI app target.
- Added internal package targets for the planned domain boundaries:
  - `RSSRadarCore`
  - `RSSRadarPersistence`
  - `RSSRadarFeeds`
  - `RSSRadarAI`
  - `RSSRadarProcessing`
- Added the base app folders: `App`, `Views`, `ViewModels`, and `Resources`.
- Added a minimal `NavigationSplitView` shell with the documented MVP sections: Today, Topics, Feeds, Processing, and Settings.
- Added a minimal XCTest target, `RSSRadarCoreTests`, with one skeleton test that loads the core module.
- No external dependencies were introduced in this step.
- User verified the build/tests passed before moving past this milestone.

Next step: implementation-plan Step 2, add basic engineering quality tooling and local SwiftLint setup without introducing dependencies that are deferred by the technical plan.

## 2026-05-20 - Step 2: basic engineering quality tooling

Completed implementation-plan Step 2.

- Added `.gitignore` for local macOS, SwiftPM, and Xcode build artifacts.
- Added `.swiftlint.yml` with a scoped SwiftLint configuration for `Package.swift`, app sources, packages, and tests.
- Added `Scripts/lint.sh` as the local lint entry point. It requires a local `swiftlint` executable and uses `.build/swiftlint-cache` so lint does not depend on user Library cache write access.
- Added `Makefile` targets:
  - `make build`
  - `make test`
  - `make lint`
  - `make verify`
- Installed local SwiftLint via Homebrew on this machine for verification (`swiftlint` 0.63.2).
- Confirmed Swift Package Manager still reports no external dependencies.
- Did not add GRDB, FeedKit, SwiftSoup, SwiftFormat, CI, or any deferred production dependencies.

Verification:

- `Scripts/lint.sh` passed with 0 violations.
- `make verify` passed and ran lint plus `swift test`.
- `swift package show-dependencies` reported: `No external dependencies found`.

User verified Step 2 before moving to Step 3.

## 2026-05-20 - Step 3: core domain models

Completed implementation-plan Step 3.

- Replaced the Core placeholder file with focused domain model files under `RSSRadarCore`.
- Added `DomainID.make()` as the shared UUID string generator for new domain object IDs.
- Added Codable, Equatable, Sendable core models:
  - `Feed`
  - `Article`
  - `ArticleAnalysis`
  - `Topic`
  - `TopicArticle`
  - `TopicBrief`
  - `AppSettings`
- Added status and configuration enums for feed state, article state, content source, article content type, topic state, topic contribution type, brief type, AI provider kind, and scan mode.
- Added explicit snake_case `CodingKeys` so encoded JSON matches the product data design and the future SQLite JSON/text boundary.
- Added default values aligned with the product and technical docs:
  - new IDs default to UUID strings
  - `Feed.status` defaults to `active`
  - `Article.status` defaults to `fetched`
  - `Topic.status` defaults to `candidate`
  - `AppSettings` defaults to OpenAI-compatible, `https://api.openai.com/v1`, manual scan, 6 hour interval, 100 max articles per scan, 20 max new-feed articles, 20 topic batch size, and 60 second AI timeout.
- Added model tests for default values, encoding/decoding round trips, encoded key names, and UUID string generation.
- Added enum tests confirming invalid raw values throw decode errors instead of being silently accepted.
- Did not add SQLite, GRDB, repositories, migrations, RSS parsing, AI provider code, or any Step 4+ functionality.

Verification:

- `swift test` passed with 18 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 18 Swift files.

Stop point: user verified Step 3. Next step is implementation-plan Step 4, SQLite and migration mechanism.

## 2026-05-20 - Step 4: SQLite and migration mechanism

Completed implementation-plan Step 4.

- Added GRDB.swift as the first production dependency for the persistence layer.
- Added `Package.resolved` pinning `GRDB.swift` at `6.29.3`.
- Replaced the persistence placeholder with `RSSRadarDatabase`, a GRDB-backed SQLite database entry point.
- Configured SQLite with:
  - WAL journal mode
  - `foreign_keys = ON`
  - `busy_timeout = 5000`
- Added a versioned GRDB migration named `v1_create_initial_schema`.
- Created the initial schema for Step 4 core data tables:
  - `feeds`
  - `articles`
  - `article_analyses`
  - `topics`
  - `topic_articles`
  - `topic_briefs`
  - `app_settings`
- Stored SQLite time fields as ISO8601 text columns.
- Stored array/nested model fields as JSON text columns using explicit `_json` suffixes.
- Added CHECK constraints for known enum/status fields so invalid database values are rejected.
- Added foreign keys and cascade deletes from feeds to articles and analyses, and from topics/articles to topic relationships and briefs.
- Added indexes for expected lookup paths such as articles by feed, article analysis by article, topics by status, and briefs by topic.
- Added `RSSRadarPersistenceTests` with temporary SQLite database migration coverage.
- Did not implement Repository CRUD, settings persistence behavior, Keychain storage, RSS parsing, processing jobs, operation logs, or Step 5+ features.

Verification:

- `swift test` passed with 24 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 19 Swift files.
- `swift package show-dependencies` reported only `GRDB.swift@6.29.3`.

User verified Step 4 before moving to Step 5.

Stop point: next step is implementation-plan Step 5, create the Repository layer. Do not let UI or ViewModels access `DatabaseQueue` directly.

## 2026-05-20 - Step 5: Repository layer

Completed implementation-plan Step 5.

- Added a Repository layer for all Step 4 core objects:
  - `FeedRepository`
  - `ArticleRepository`
  - `ArticleAnalysisRepository`
  - `TopicRepository`
  - `TopicArticleRepository`
  - `TopicBriefRepository`
- Added `RSSRadarRepositories` as the public persistence entry point for service/view-model code that needs repositories.
- Added `RSSRadarRepositoryTransaction` and `RSSRadarRepositories.performTransaction(_:)` so multi-object writes can be executed atomically and rolled back on failure.
- Added internal database access plumbing that lets repository methods run either against the shared `DatabaseQueue` or inside an existing GRDB transaction.
- Added shared database coding helpers for:
  - ISO8601 text date encoding/decoding
  - URL string conversion
  - JSON TEXT conversion for array and nested fields
  - row mapping error cases
- Changed `RSSRadarDatabase.queue` from public to internal so app/UI code cannot directly access `DatabaseQueue`; tests in the same target can still inspect migration behavior.
- Implemented upsert behavior matching current schema constraints:
  - object ID upserts for feeds, articles, and topics
  - `article_analyses.article_id` upsert for one stable analysis per article
  - `(topic_id, article_id)` upsert for topic/article relationships
  - `(topic_id, brief_type)` upsert for one current brief cache per type
- Added candidate topic normalized-name lookup using the schema's `topics.normalized_name` column.
- Added `RepositoryTests` using temporary SQLite databases to verify CRUD, status/list queries, JSON round trips, upserts, relationship writes, deletes, and transaction rollback.
- Did not implement settings persistence behavior, Keychain storage, RSS parsing, processing jobs, operation logs, AI provider code, or Step 6+ functionality.

Verification:

- User verified this step after local testing.
- `swift test` passed with 31 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 28 Swift files.

Stop point: next step is implementation-plan Step 6, implement settings persistence. Do not start Step 6 until explicitly requested.

## 2026-05-20 - Step 6: settings persistence

Completed implementation-plan Step 6.

- Added `AppSettingsRepository` for the `app_settings` table.
- Exposed `appSettings` through `RSSRadarRepositories` and `RSSRadarRepositoryTransaction`, keeping settings persistence behind the same Repository boundary as the rest of the database layer.
- Implemented `fetch()` so an empty database returns the documented `AppSettings()` defaults without inserting a row as a side effect.
- Implemented `save(_:updatedAt:)` as a singleton-row upsert using `id = 'default'`.
- Persisted only non-secret settings:
  - AI provider
  - Base URL
  - model name
  - database path
  - Keychain account identifier
  - scan mode
  - scan interval
  - article and topic processing limits
  - AI request timeout
- Added explicit integer row decoding in `DatabaseCoding` for settings numeric fields.
- Added repository tests for:
  - default settings when no row exists
  - save/read round trip
  - upsert behavior for the default settings row
  - invalid provider CHECK constraint rejection
  - confirming the settings schema and stored text values do not contain an API Key plaintext field or value
- Did not implement macOS Keychain storage, API Key save/read/delete, Settings UI, database path switching orchestration, RSS parsing, processing jobs, operation logs, or Step 7+ functionality.

Verification:

- User verified this step after local testing.
- `swift test` passed with 35 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 29 Swift files.

Stop point: next step is implementation-plan Step 7, implement Keychain API Key storage. Do not start Step 7 until explicitly requested.

## 2026-05-20 - Step 7: Keychain API Key storage

Completed implementation-plan Step 7.

- Added `KeychainAPIKeyStore` in the persistence module as the macOS Keychain boundary for AI API Key storage.
- Linked the `RSSRadarPersistence` target against Apple's `Security` framework; no third-party dependency was added for Keychain support.
- Implemented API Key operations:
  - save
  - read
  - replace through save/upsert behavior
  - delete
- Added `KeychainAPIKeyStore.makeAccountIdentifier()` so Settings/UI code can create an opaque account identifier and persist only that identifier in `AppSettings.keychainAccountIdentifier`.
- Kept API Key plaintext out of SQLite. `AppSettingsRepository` remains responsible only for the non-secret `keychain_account_identifier`.
- Added validation for empty account identifiers and empty API Keys.
- Added Keychain error mapping that avoids including API Key plaintext in user-visible error descriptions.
- Added `KeychainAPIKeyStoreTests` using an isolated per-test Keychain service name. The tests clean up every account identifier they create.
- Did not implement Settings UI, Keychain/account orchestration in ViewModels, RSS parsing, FeedKit, manual feed add, processing jobs, or Step 8+ functionality.

Verification:

- User verified this step after local testing.
- `swift test` passed with 40 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 31 Swift files.

Stop point: next step is implementation-plan Step 8, implement manual RSS feed add. Do not start Step 8 until explicitly requested.

## 2026-05-20 - Step 8: manual RSS feed add

Completed implementation-plan Step 8.

- Added FeedKit as the RSS/Atom/JSON Feed parsing dependency for the feed module.
- Updated `Package.resolved` to lock:
  - `FeedKit` at `9.1.2`
  - existing `GRDB.swift` at `6.29.3`
- Replaced the `RSSRadarFeeds` placeholder with manual feed add primitives:
  - `FeedDataLoader` for injectable async feed data loading
  - `FeedStore` for persistence boundary injection
  - `ManualFeedAddService` for URL validation, feed fetch, metadata parse, status selection, and optional save
  - `ManualFeedAddError` for invalid manual RSS URL input
- Added `FeedMetadataParser` backed by FeedKit. It extracts feed title, site URL, and article presence from RSS, Atom, and JSON Feed metadata.
- Added status behavior for manually added feeds:
  - valid feed with items becomes `active`
  - valid feed without items becomes `no_articles`
  - HTTP failure or parse failure becomes `error` with a non-crashing `errorMessage`
  - invalid URL input throws before saving anything
- Added `ManualFeedAddUseCase` in `RSSRadarProcessing` to connect the feed service to the real `FeedRepository`, preserving the rule that UI/ViewModels call use cases/services rather than accessing SQLite directly.
- Added RSS fixture tests for:
  - valid RSS metadata
  - empty RSS feed
  - invalid feed XML
  - HTTP status failure
  - invalid URL validation
- Added repository-backed processing tests that verify successful and failed manual feed adds are persisted through SQLite.
- Did not implement OPML import, article entry ingestion, URL/title deduplication, feed scan progress advancement, content extraction, processing jobs, or Step 9+ functionality.

Verification:

- User verified this step after local testing.
- `swift test` passed with 47 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 35 Swift files.

Stop point: next step is implementation-plan Step 9, implement OPML import. Do not start Step 9 until explicitly requested.

## 2026-05-20 - Step 9: OPML import

Completed implementation-plan Step 9.

- Added OPML import support in the feeds module using Foundation `XMLParser`; no new third-party dependency was introduced.
- Added `OPMLImportService`, `OPMLFeedStore`, `OPMLImportResult`, duplicate records, and error records as the feed-module boundary for importing OPML into `Feed` objects.
- Parsed OPML `outline` attributes:
  - `text`
  - `title`
  - `xmlUrl`
  - `htmlUrl`
- Supported grouped OPML outlines. Group/container outlines are not imported as feeds; leaf outlines without `xmlUrl` are reported as errors.
- Imported valid HTTP/HTTPS `xmlUrl` entries as `Feed` rows with `active` status, using `title` first, then `text`, then feed host as the display title fallback.
- Preserved `htmlUrl` as `Feed.siteURL` when present and parseable.
- Skipped duplicate sources using existing repository feeds plus URLs already seen in the current OPML document.
- Recorded invalid or missing `xmlUrl` entries in the import result instead of crashing or creating broken feeds.
- Added `OPMLImportUseCase` in `RSSRadarProcessing` to connect OPML import to the real `FeedRepository`, preserving the rule that UI/ViewModels call use cases rather than writing repositories directly.
- Reused the repository-backed feed store adapter for both manual add and OPML import.
- Added OPML fixtures and tests covering:
  - grouped outlines
  - title/text/host fallback behavior
  - `htmlUrl` mapping
  - missing `xmlUrl`
  - invalid `xmlUrl`
  - duplicate sources within the OPML document
  - duplicate sources already present in the database
  - invalid XML parse failure
  - repository-backed persistence through the processing use case
- Did not implement feed article fetching, article entry ingestion, URL/title article deduplication, feed scan progress advancement, content extraction, processing jobs, or Step 10+ functionality.

Verification:

- User verified this step after local testing.
- `swift test` passed with 51 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 39 Swift files.

Stop point: next step is implementation-plan Step 10, implement Feed fetching and Article persistence. Do not start Step 10 until explicitly requested.

## 2026-05-20 - Step 10: Feed fetching and Article persistence

Completed implementation-plan Step 10.

- Added feed scan support in the feeds module using the existing `FeedDataLoader` abstraction and FeedKit dependency.
- Added `FeedArticleParser` to parse RSS, Atom, and JSON Feed entries into normalized article candidates:
  - title
  - URL
  - author
  - published date
  - RSS summary
  - feed-provided full content
- Added `FeedScanService` as the feed-module boundary for scanning one feed, selecting articles, and calculating the updated `Feed` state.
- Implemented the Step 10 selection and progress rules:
  - new feeds keep at most the 20 newest entries
  - published entries are sorted newest first
  - entries without `published_at` sort after dated entries
  - existing feeds only keep entries whose `published_at` is after `last_processed_article_published_at`
  - undated articles are saved for new feeds but do not advance `last_processed_article_published_at`
  - feed progress advances to the newest successfully selected article with a publication date
  - feeds with parsed entries remain `active` even when there are no new articles after the current progress marker
  - feeds with no parsed entries become `no_articles`
  - HTTP or parse failures mark the feed `error` while preserving previous success/progress timestamps
- Added `FeedScanUseCase` in `RSSRadarProcessing` to connect scanning to real repositories. It fetches the persisted feed, scans it, then saves selected `Article` rows and the updated `Feed` in one repository transaction.
- Kept article persistence behind `ArticleRepository`; UI/ViewModels should call `FeedScanUseCase` or later processing orchestration, not write articles directly during feed scans.
- Added feed scan fixtures and tests covering:
  - new source limit of 20 articles
  - existing source filtering by `last_processed_article_published_at`
  - no-new-articles scans preserving active feed status and progress
  - undated article behavior
  - HTTP failure behavior
  - repository-backed article and feed progress persistence
  - missing feed error handling
- Did not implement Step 11 article deduplication:
  - no URL canonicalization
  - no tracking parameter stripping
  - no fragment stripping
  - no title similarity matching
- Did not implement content extraction, processing jobs, operation logs, parse-article job creation, AI analysis, topic assignment, or Step 11+ functionality.

Verification:

- User verified this step after local testing.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 44 Swift files.
- `swift test` passed with 58 tests and 0 failures.

Stop point: next step is implementation-plan Step 11, implement article deduplication. Do not start Step 11 until explicitly requested.

## 2026-05-20 - Step 11: Article deduplication

Completed implementation-plan Step 11.

- Added `ArticleDeduplicator` in the feeds module as the pure article deduplication rule component.
- Implemented Article URL canonicalization:
  - lowercases scheme and host
  - removes URL fragment
  - removes common tracking query parameters such as `utm_*`, `fbclid`, `gclid`, `gbraid`, `wbraid`, `mc_cid`, `mc_eid`, `igshid`, `yclid`, `_hsenc`, `_hsmi`, `spm`, and `mkt_tok`
  - sorts remaining query parameters for stable comparison
- Implemented URL-based deduplication across existing persisted articles and the current scan batch.
- Implemented title-similarity deduplication only within the same feed.
- Kept similar titles from different feeds, so multiple sources can cover the same story without being incorrectly collapsed.
- Connected deduplication in `FeedScanUseCase`, after `FeedScanService` returns selected scan articles and before repository persistence.
- Kept `FeedScanService` free of repository access. It still handles feed loading, FeedKit parsing, article selection, and scan status calculation; repository-aware deduplication remains in the processing use case.
- Updated feed progress after deduplication so `last_processed_article_published_at` advances only to the newest published article that was actually kept for persistence.
- Preserved existing error and empty-result behavior:
  - failed scans still save the scanned error feed unchanged
  - active scans with all selected articles deduplicated keep the previous progress marker
- Added feeds-module unit tests for:
  - canonical URL behavior
  - URL duplicate elimination
  - same-feed title similarity elimination
  - different-feed similar title retention
- Added processing integration tests and a dedicated `dedup-rss.xml` fixture covering:
  - persisted URL duplicate skipped during scan
  - same-feed near-duplicate title skipped during scan
  - distinct article retained
  - feed progress based on retained articles
  - similar title from another feed not suppressing the source feed's article
- Did not implement Step 12 content extraction:
  - no SwiftSoup dependency added
  - no webpage HTML fetch
  - no RSS summary fallback parsing stage beyond existing stored RSS fields
- Did not implement processing jobs, operation logs, parse-article job creation, AI analysis, topic assignment, or Step 12+ functionality.

Verification:

- `swift test` passed with 64 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 46 Swift files.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 12, implement content extraction and fallback. Do not start Step 12 until explicitly requested.

## 2026-05-20 - Step 12: Content extraction and fallback

Completed implementation-plan Step 12.

- Added SwiftSoup as the HTML parsing dependency for the feeds module.
- Updated `Package.resolved` to lock `SwiftSoup` at `2.13.5`.
- Added `ArticleContentExtractionService` in the feeds module as the article content parsing boundary.
- Implemented article content source priority:
  - RSS full content first
  - webpage body extraction second
  - RSS summary fallback last
- Normalized RSS full content and RSS summary through SwiftSoup text extraction so stored article content does not retain HTML tags.
- Added lightweight webpage extraction rules:
  - remove `script`, `style`, `nav`, `header`, `footer`, `aside`, `noscript`, `svg`, and `form`
  - prefer `article`, `main`, `[role=main]`, and common content class selectors
  - score candidates by text length, paragraph count, and link text penalty
  - fall back to paragraph aggregation when no obvious content container is usable
  - reject very short extracted bodies and fall back to RSS summary
- Connected content extraction into `FeedScanService` after article selection and before returning scan results to the processing use case.
- Scanned articles now enter persistence with:
  - `content` filled from the best available source
  - `content_source` set to `rss_full_content`, `web_extracted`, or `rss_summary`
  - `status` set to `parsed`
- Preserved previous feed scan and deduplication boundaries:
  - `FeedScanService` still does not access repositories
  - `FeedScanUseCase` still performs repository-aware deduplication and transaction persistence
  - feed progress is still calculated from articles retained after deduplication
- Added feeds-module tests and HTML fixtures covering:
  - RSS full content takes priority and does not fetch webpage content
  - extractable HTML produces `web_extracted` content and removes navigation/footer noise
  - unextractable HTML falls back to RSS summary
- Did not implement Step 13 local processing queue:
  - no `processing_jobs` table
  - no `operation_logs` table
  - no parse-article job creation
  - no `ProcessingEngine`
- Did not implement AI analysis, topic assignment, TopicBrief generation, or Step 13+ functionality.

Verification:

- `swift test` passed with 67 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 48 Swift files.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 13, establish `processing_jobs` and `operation_logs`. Do not start Step 13 until explicitly requested.

## 2026-05-20 - Step 13: processing_jobs and operation_logs

Completed implementation-plan Step 13.

- Added Core domain models for the local processing queue and user-visible processing log:
  - `ProcessingJob`
  - `OperationLog`
- Added queue enums covering the required Step 13 job types:
  - `fetch_feed`
  - `parse_article`
  - `analyze_article`
  - `assign_topics`
  - `generate_topic_brief`
  - `retry_failed_job`
- Added `ProcessingJobStatus` values for persisted job lifecycle state:
  - `pending`
  - `running`
  - `completed`
  - `failed`
- Added `operation_logs` levels:
  - `info`
  - `warning`
  - `error`
- Extended the v1 SQLite migration with:
  - `processing_jobs`
  - `operation_logs`
- Added CHECK constraints for processing job type, entity type, job status, and operation log level.
- Added indexes for ready-job lookup and processing page queries:
  - `idx_processing_jobs_status_schedule`
  - `idx_processing_jobs_entity`
  - `idx_operation_logs_created_at`
- Added `ProcessingJobRepository` with support for:
  - save/upsert
  - fetch by ID
  - list all jobs
  - list by status
  - list ready pending jobs by scheduled time, priority, and limit
  - status updates
  - delete
- Added `OperationLogRepository` with support for:
  - save/upsert
  - fetch by ID
  - list all logs
  - fetch recent logs
  - delete
- Exposed `processingJobs` and `operationLogs` through `RSSRadarRepositories` and `RSSRadarRepositoryTransaction`.
- Added a conservative operation-log validation guard that rejects obvious sensitive content markers such as API key labels, bearer tokens, and `sk-` style key values before writing user-visible logs.
- Added Core model and enum tests for the new queue/log types.
- Added migration tests verifying the new tables and CHECK constraints.
- Added repository tests for job creation, status changes, ready-job ordering, payload round trips, failed-job fields, operation log writes, recent log reads, deletion, and sensitive log rejection.
- Did not implement Step 14 ProcessingEngine:
  - no actor-driven worker loop
  - no finite concurrency scheduling
  - no job execution dispatch
  - no startup recovery logic beyond persisted schema/repositories
- Did not implement Step 15 retry policy or Step 16 abnormal-exit recovery.

Verification:

- User verified this step after local testing.
- `swift test` passed with 78 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 52 Swift files.

Stop point: next step is implementation-plan Step 14, implement `ProcessingEngine`. Do not start Step 14 until explicitly requested.

## 2026-05-20 - Step 14: ProcessingEngine

Completed implementation-plan Step 14.

- Added `ProcessingEngine` as the actor-driven local processing queue orchestrator in the processing module.
- Added `ProcessingEngineConfiguration` with per-job-type concurrency limits aligned with the technical plan:
  - feed fetch: 4 by default
  - article parse/extraction: 3 by default
  - AI article analysis: 2 by default
  - topic assignment: 1 by default
  - TopicBrief generation: 1 by default
- Added `ProcessingJobExecuting` as the job execution protocol so tests and future AI/topic workers can be injected without changing the engine.
- Added `ProcessingEngineExecutor` as the default executor. Current concrete execution supports `fetch_feed` jobs by calling `FeedScanUseCase`; later AI/topic job types intentionally remain unsupported until their implementation steps.
- Added queue entry points:
  - `enqueueFeedScan(feedID:)`
  - `enqueueScanAllFeeds()`
  - `runPendingJobs(now:)`
- Ensured queued feed scans are persisted as `processing_jobs` rows and create user-visible `operation_logs`.
- Implemented pending-job selection through `ProcessingJobRepository.fetchReady`, keeping job state durable rather than in memory only.
- Implemented per-run finite concurrency by selecting ready jobs per `ProcessingJobType` according to configuration limits.
- Implemented successful job state flow:
  - `pending`
  - `running`
  - `completed`
- Wrote start/completion logs with non-sensitive context such as `job_id`, `feed_id`, and `job_type`.
- Implemented a basic failure terminal path that marks a job `failed` and records a sanitized user-visible failure log.
- Did not implement Step 15 retry policy:
  - no attempt-count increment
  - no retry backoff scheduling
  - no manual retry entry point
- Did not implement Step 16 abnormal-exit recovery:
  - no startup conversion of stale `running` jobs back to `pending`
  - no recovery-specific tests
- Did not implement AI analysis, topic assignment, TopicBrief generation, or retry job execution.

Verification:

- User verified this step after local testing.
- `swift test` passed with 81 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 54 Swift files.

Stop point: next step is implementation-plan Step 15, implement failure retry strategy. Do not start Step 15 until explicitly requested.

## 2026-05-20 - Step 15: Failure retry strategy

Completed implementation-plan Step 15.

- Extended `ProcessingEngineConfiguration` with retry backoff settings.
- Implemented the automatic retry policy in `ProcessingEngine`:
  - first failed attempt increments `attempt_count` and immediately reschedules the job as `pending`
  - second failed attempt increments `attempt_count` and reschedules the job 30 seconds later
  - third failed attempt reaches `max_attempts = 3` and marks the job `failed`
- Added retry-state persistence through `ProcessingJobRepository.updateRetryState(...)`, keeping retry updates in the repository layer rather than hand-written SQL in the engine.
- Added `ProcessingEngine.retry(jobID:scheduledAt:)` as the user/manual retry entry point for failed jobs.
- Manual retry behavior:
  - only accepts jobs currently in `failed`
  - changes the job back to `pending`
  - resets `attempt_count` to 0
  - clears `last_error_message`, `started_at`, and `finished_at`
  - writes a user-visible info operation log
- Failed attempts now write warning operation logs when the job is scheduled for automatic retry, and error operation logs when max attempts are exhausted.
- Confirmed a failing job does not block other ready jobs in the same processing run.
- Kept Step 16 out of scope:
  - no startup recovery API
  - no conversion of stale `running` jobs back to `pending`
  - no abnormal-exit recovery tests
- Did not implement AI analysis, topic assignment, TopicBrief generation, or real execution for `retry_failed_job`.

Verification:

- User verified this step after local testing.
- `swift test` passed with 85 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 55 Swift files.

Stop point: next step is implementation-plan Step 16, verify abnormal-exit recovery. Do not start Step 16 until explicitly requested.

## 2026-05-20 - Step 16: Abnormal-exit recovery

Completed implementation-plan Step 16.

- Added persisted startup recovery for interrupted processing jobs.
- Added `ProcessingJobRepository.recoverInterruptedJobs(...)` to convert stale `running` jobs back to `pending`.
- Recovery behavior:
  - only touches jobs whose status is `running`
  - preserves `attempt_count`
  - clears stale `started_at` and `finished_at`
  - updates `scheduled_at` so recovered jobs are immediately eligible for the next processing run
  - leaves `pending`, `completed`, and `failed` jobs unchanged
- Added `ProcessingEngine.recoverInterruptedJobs(now:)` as the engine-level startup recovery entry point.
- Recovery writes a warning-level operation log when at least one interrupted job is recovered.
- Added repository tests confirming interrupted `running` jobs recover without increasing attempts and unrelated jobs are unchanged.
- Added processing engine tests confirming recovered jobs and existing pending jobs execute, while completed jobs are not repeated.
- Did not implement Step 17 AI Provider abstraction:
  - no OpenAI-compatible request code
  - no Anthropic request code
  - no Custom Base URL provider
  - no AI request timeout/cancellation/error mapping beyond existing queue behavior

Verification:

- User verified this step after local testing.
- `swift test` passed with 87 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 55 Swift files.

Stop point: next step is implementation-plan Step 17, implement AI Provider abstraction. Do not start Step 17 until explicitly requested.

## 2026-05-21 - Step 17: AI Provider abstraction

Completed implementation-plan Step 17.

- Added the AI Provider abstraction in `RSSRadarAI`:
  - `AIProvider`
  - `AIProviderRequest`
  - `AIProviderResponse`
  - `AIMessage`
  - `AIProviderConfiguration`
  - `AIProviderError`
- Implemented `URLSessionAIProvider` for the three documented provider kinds:
  - OpenAI-compatible
  - Anthropic
  - Custom Base URL
- Confirmed default provider base URLs:
  - OpenAI-compatible: `https://api.openai.com/v1`
  - Anthropic: `https://api.anthropic.com`
  - Custom defaults to the OpenAI-compatible base URL unless the caller supplies another base URL
- Implemented OpenAI-compatible and Custom requests using Chat Completions format at `/chat/completions`.
- Implemented Anthropic requests using Messages API format at `/v1/messages`, including `x-api-key` and `anthropic-version` headers.
- Added unified request validation for missing API Key, missing model, and empty messages before any network request is made.
- Added timeout, cancellation, HTTP status, network, invalid base URL, and invalid response mapping through `AIProviderError` with user-understandable descriptions.
- Added `Tests/RSSRadarAITests` as a dedicated AI module test target.
- Added tests using both:
  - `FakeAIProvider` to verify callers can depend on the protocol abstraction
  - `URLProtocol` mock to verify exact request URLs, headers, JSON body shape, timeout interval, successful response decoding, and error mapping
- Kept Step 18 out of scope:
  - no Prompt resource files
  - no Prompt loading API
  - no article analysis prompt construction
- Kept Step 19+ out of scope:
  - no AI JSON schema validation
  - no `ArticleAnalysis` persistence from AI output
  - no `ProcessingEngine` execution path for `analyze_article`
  - no topic assignment or TopicBrief generation

Verification:

- User verified this step after local testing.
- `swift test` passed with 95 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 58 Swift files.

Stop point: next step is implementation-plan Step 18, implement Prompt management. Do not start Step 18 until explicitly requested.

## 2026-05-21 - Step 18: Prompt management

Completed implementation-plan Step 18.

- Added built-in Prompt resource handling to the `RSSRadarAI` target.
- Added four Markdown Prompt templates under `Packages/RSSRadarAI/Sources/RSSRadarAI/Prompts/`:
  - `ArticleAnalysisPrompt.md`
  - `TopicAssignmentPrompt.md`
  - `TopicBriefPrompt.md`
  - `CandidateTopicPreviewPrompt.md`
- Added `PromptTemplateKind`, `PromptTemplate`, `PromptTemplateStore`, and `PromptTemplateError` as the AI module's Prompt loading boundary.
- Implemented resource-backed template loading from the SwiftPM `.module` bundle.
- Implemented simple `{{variable}}` rendering for prompt inputs.
- Added conservative prompt-input sanitization that rejects obvious sensitive markers such as API key labels, authorization headers, bearer tokens, `x-api-key`, and `sk-` style values before rendering.
- Added `PromptTemplateStoreTests` covering:
  - loading every built-in template
  - rendering expected article-analysis inputs
  - missing-template errors with clear user-understandable messages
  - rejection of sensitive prompt inputs
- Kept Step 19 out of scope:
  - no AI call orchestration for article analysis
  - no AI JSON schema validation
  - no `ArticleAnalysis` parsing or persistence
  - no `ProcessingEngine` execution path for `analyze_article`

Verification:

- User verified this step after local testing.
- `swift test --filter RSSRadarAITests` passed with 12 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 60 Swift files.
- `swift test` passed with 99 tests and 0 failures.

Stop point: next step is implementation-plan Step 19, implement single-article analysis. Do not start Step 19 until explicitly requested.

## 2026-05-21 - Step 19: Single-article analysis

Completed implementation-plan Step 19.

- Added `ArticleAnalyzing` and `ArticleAnalysisService` in `RSSRadarAI`.
- Implemented the successful single-article AI analysis flow:
  - load the built-in article analysis Prompt
  - render title, source, published time, URL, RSS summary, and content
  - call the injected `AIProvider`
  - decode the provider response as structured JSON
  - validate required summary and `importance_score` range
  - normalize string arrays by trimming empty values
  - return an `ArticleAnalysis` domain model
- Added `ArticleAnalysisValidationError` for invalid UTF-8, invalid JSON, empty required fields, and out-of-range importance scores.
- Added `ArticleAnalysisUseCase` in `RSSRadarProcessing` to connect analysis to repositories:
  - fetch the target article
  - fetch its source feed title when available
  - invoke an injected `ArticleAnalyzing`
  - save `ArticleAnalysis`
  - mark the article as `analyzed`
  - copy `importance_score` back to the article
  - clear prior article error text
  - persist analysis and article update in one repository transaction
- Extended `ProcessingEngineExecutor` so `analyze_article` jobs can run when an `ArticleAnalyzing` implementation is explicitly injected.
- Kept the default executor's feed scan path unchanged.
- Added `Tests/RSSRadarAITests/Fixtures/article-analysis.json` as the fixed successful AI JSON fixture for Step 19.
- Added AI module tests verifying the fixture is parsed into all required `ArticleAnalysis` fields and the rendered prompt/request contains article inputs.
- Added processing tests verifying repository-backed analysis persistence, article status update, article importance update, and `analyze_article` job execution through `ProcessingEngineExecutor`.
- Updated `Package.swift` so `RSSRadarAITests` can process fixtures and `RSSRadarProcessingTests` can import `RSSRadarAI` test doubles.
- Did not implement Step 20:
  - no invalid JSON fixture coverage for processing failure flow
  - no final article `failed` marking after unrecoverable AI JSON validation failure
  - no special retry/failure handling beyond the existing `ProcessingEngine` generic job retry mechanism
- Did not implement topic assignment, TopicBrief generation, candidate topic preview generation, or UI wiring.

Verification:

- `swift test --filter RSSRadarAITests` passed with 13 tests and 0 failures.
- `swift test --filter RSSRadarProcessingTests` passed with 16 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 64 Swift files.
- `swift test` passed with 102 tests and 0 failures.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 20, implement AI JSON validation failure handling. Do not start Step 20 until explicitly requested.

## 2026-05-21 - Step 20: AI JSON validation failure handling

Completed implementation-plan Step 20.

- Extended `ProcessingEngine` failure handling for exhausted `analyze_article` jobs whose underlying error is `ArticleAnalysisValidationError`.
- AI JSON validation failures now keep using the existing durable retry flow first:
  - retryable failures return the job to `pending`
  - attempt counts and retry scheduling are persisted in `processing_jobs`
  - warning logs are written for automatic retries
- When an `analyze_article` job exhausts attempts because of invalid AI analysis output:
  - the job is marked `failed`
  - the target `Article` is marked `failed`
  - the article receives a non-secret validation error message
  - no `ArticleAnalysis` row is written
  - the existing error operation log is retained for the Processing page
- Kept `ArticleAnalysisService` as the pure AI parsing and validation boundary. It still does not access repositories, processing jobs, or operation logs.
- Added invalid-output test coverage in `RSSRadarAITests` for:
  - malformed JSON fixture
  - empty required `summary`
  - invalid `content_type` enum
- Added `Tests/RSSRadarAITests/Fixtures/article-analysis-invalid.json` as the malformed AI JSON fixture.
- Added processing integration coverage confirming exhausted validation failure marks the article failed and leaves `article_analyses` empty.
- Did not implement Step 21:
  - no topic assignment prompt execution
  - no Topic or TopicArticle creation from batches
  - no broad topic-name validation

Verification:

- `swift test --filter RSSRadarAITests` passed with 16 tests and 0 failures.
- `swift test --filter RSSRadarProcessingTests` passed with 17 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 64 Swift files.
- `swift test` passed with 106 tests and 0 failures.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 21, implement batch topic generation and matching. Do not start Step 21 until explicitly requested.

## 2026-05-21 - Step 21: Batch topic generation and matching

Completed implementation-plan Step 21.

- Added `TopicAssigning`, `TopicAssignmentService`, `TopicAssignmentResult`, `TopicAssignment`, and `NewTopicCandidate` in `RSSRadarAI`.
- Implemented the batch topic assignment flow:
  - load the built-in topic assignment Prompt
  - render analyzed article JSON and existing topic JSON
  - call the injected `AIProvider`
  - parse assignment JSON
  - validate article IDs, existing topic IDs, confidence range, reason, contribution type, and new topic fields
  - normalize string fields before returning typed assignments
- Added local broad-topic-name validation for new candidate topics. At the time, broad names such as `AI` were rejected by `TopicAssignmentValidationError`; this was later superseded by the 2026-05-28 entity/dimension anchored topic strategy, which allows meaningful industry, asset, and technology dimensions.
- Supported one article appearing in multiple assignments so a single article can be linked to multiple topics.
- Added `TopicAssignmentUseCase` in `RSSRadarProcessing` to connect topic assignments to repositories:
  - load up to 20 article analyses per batch
  - load active and candidate topics as existing topics for assignment
  - invoke an injected `TopicAssigning`
  - create new `candidate` topics when AI proposes specific new topics
  - save `TopicArticle` relationships for existing and new topics
  - mark assigned articles as `assigned`
  - persist topic, relationship, and article updates in one repository transaction
- Added `ProcessingEngine.enqueueTopicAssignment(...)`, which splits article IDs into 20-article batches and persists `assign_topics` jobs with non-secret payload values.
- Extended `ProcessingEngineExecutor` so `assign_topics` jobs can run when a `TopicAssigning` implementation is explicitly injected.
- Added `Tests/RSSRadarAITests/Fixtures/topic-assignment.json` as the fixed successful AI JSON fixture for topic assignment.
- Added AI module tests covering existing-topic assignment, new candidate topic assignment, multiple assignments for one article, Prompt request content, broad-topic rejection, and unknown topic rejection. The broad-topic rejection coverage was later replaced by 2026-05-28 tests for allowed dimension topics and rejected meaningless generic names.
- Added processing integration tests covering repository-backed topic creation, relationship persistence, article `assigned` status updates, `assign_topics` job execution through `ProcessingEngineExecutor`, and 20-article job batching.
- Kept Step 22 out of scope:
  - no candidate topic list or detail data source
  - no candidate preview generation
  - no candidate-to-active or candidate-to-ignored state transitions
  - no user-facing rename or description-edit flow
  - no same-status candidate topic management beyond in-batch new-topic reuse
- Did not implement active topic continuous update, user correction records, TopicBrief generation, Today data source, Topic Detail data source, Markdown export, or UI wiring.

Verification:

- `swift test --filter RSSRadarAITests` passed with 19 tests and 0 failures.
- `swift test --filter RSSRadarProcessingTests` passed with 20 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 68 Swift files.
- `swift test` passed with 112 tests and 0 failures.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 22, implement candidate topic management. Do not start Step 22 until explicitly requested.

## 2026-05-21 - Step 22: Candidate topic management

Completed implementation-plan Step 22.

- Added `CandidateTopicManagementUseCase` in `RSSRadarProcessing` as the use-case boundary for candidate topic management.
- Implemented candidate topic listing and single-candidate preview data:
  - topic metadata
  - existing preview `TopicBrief` cache when present
  - related `Article` rows through `TopicArticle`
  - relationship/article count for compact preview surfaces
- Implemented candidate status actions:
  - candidate to active via `trackCandidate`
  - candidate to ignored via `ignoreCandidate`
- Implemented candidate editing actions:
  - rename candidate topic
  - update candidate description
  - trim user input before persistence
  - reject empty names and descriptions
- Added same-status candidate normalized-name protection:
  - candidate rename rejects another candidate with the same normalized name
  - topic assignment now reuses an existing candidate with the same normalized name instead of creating a duplicate candidate topic
- Kept all candidate management writes behind `TopicRepository` and use cases; no UI, ViewModel, or direct SQLite access was added.
- Added processing tests covering:
  - candidate to active state transition
  - candidate to ignored state transition
  - rename persistence
  - description persistence
  - candidate preview including preview brief and related articles
  - non-candidate action rejection
  - duplicate candidate rename rejection
  - topic assignment reuse of an existing same-normalized-name candidate
- Did not implement Step 23:
  - no active topic continuous update
  - no simulated follow-up scan using user-edited active topic names/descriptions
  - no pre-generation of full TopicBrief for active topics
- Did not implement user correction records, TopicBrief generation, Today data source, Topic Detail data source, Markdown export, or UI wiring.

Verification:

- `swift test --filter RSSRadarProcessingTests` passed with 26 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 70 Swift files.
- `swift test` passed with 118 tests and 0 failures.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 23, implement Active Topic continuous update. Do not start Step 23 until explicitly requested.

## 2026-05-21 - Step 23: Active Topic continuous update

Completed implementation-plan Step 23.

- Extended `TopicAssignmentUseCase` so active topics continue participating in later topic assignment batches through the existing `TopicAssigning` input path.
- Verified and locked in the rule that user-edited active topic `name` and `description` are what get passed to the AI topic assigner, while original AI name/description remain only as internal metadata.
- When a later assignment matches an existing active topic, the existing `(topic_id, article_id)` `TopicArticle` row is upserted, so confidence, reason, contribution type, and created timestamp can be refreshed by the new scan result.
- Added Step 23 active-topic follow-up behavior: every active topic touched by a topic assignment batch now queues exactly one pending `generate_topic_brief` job for a full brief.
- The queued full brief job stores only non-secret payload values:
  - `topic_id`
  - `brief_type = full`
  - `model_name`
- Added a user-visible operation log entry when full TopicBrief generation is queued for an active topic.
- Extended `TopicAssignmentUseCaseResult` with touched active topic IDs and queued TopicBrief jobs so later UI/data-source work can inspect the follow-up work scheduled by assignment.
- Kept actual TopicBrief content generation out of scope. `generate_topic_brief` jobs are durable placeholders until Step 25 implements the real full/preview TopicBrief generation and caching path.
- Did not implement Step 24:
  - no user correction records
  - no remove-article-from-topic workflow
  - no add-article-to-existing-topic workflow
  - no create-topic-from-article workflow

Verification:

- `swift test --filter RSSRadarProcessingTests` passed with 27 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 70 Swift files.
- `swift test` passed with 119 tests and 0 failures.
- User verified this step after local testing.

Stop point: next step is implementation-plan Step 24, implement user correction records. Do not start Step 24 until explicitly requested.

## 2026-05-21 - Step 24: User correction records

Completed implementation-plan Step 24.

- Added `UserCorrection` and `UserCorrectionType` in `RSSRadarCore`.
- Added `user_corrections` to the v1 SQLite schema with CHECK constraints for the three MVP correction types:
  - remove article from topic
  - add article to topic
  - create topic from article
- Added `UserCorrectionRepository` and exposed it through `RSSRadarRepositories` and `RSSRadarRepositoryTransaction`.
- Added `UserCorrectionUseCase` in `RSSRadarProcessing` as the use-case boundary for user correction workflows.
- Implemented remove-article-from-topic:
  - verifies the topic, article, and existing relationship
  - deletes the `(topic_id, article_id)` relationship
  - records a `remove_article_from_topic` correction in the same transaction
- Implemented add-article-to-existing-topic:
  - verifies the topic and article
  - creates/upserts a manual `TopicArticle` relationship with confidence `1`
  - records an `add_article_to_topic` correction in the same transaction
- Implemented create-topic-from-article:
  - validates user-provided topic name, description, entities, and reason
  - creates an `active` topic
  - links the seed article to the new topic
  - records a `create_topic_from_article` correction in the same transaction
- Each correction result returns a flag and message indicating the user can regenerate TopicBrief after the correction.
- Kept Step 25 out of scope:
  - no TopicBrief generation
  - no TopicBrief cache reads/writes
  - no AI call for full or preview brief content
  - no `generate_topic_brief` job execution

Verification:

- User verified this step after local testing.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 75 Swift files.
- `swift test` passed with 127 tests and 0 failures.

Stop point: next step is implementation-plan Step 25, implement TopicBrief generation and caching. Do not start Step 25 until explicitly requested.

## 2026-05-21 - Step 25: TopicBrief generation and caching

Completed implementation-plan Step 25.

- Added `TopicBriefGenerating`, `TopicBriefSourceArticle`, `TopicBriefGenerationService`, and `TopicBriefValidationError` in `RSSRadarAI`.
- Implemented full active-topic TopicBrief generation and candidate-topic preview generation through the existing AI Provider and PromptTemplate boundaries:
  - active topics use `TopicBriefPrompt.md`
  - candidate topics use `CandidateTopicPreviewPrompt.md`
  - TopicBrief output defaults to Chinese through the built-in prompts
- Implemented TopicBrief AI JSON parsing and validation:
  - validates non-empty `current_takeaway`
  - validates evidence text and evidence `article_id`
  - rejects evidence or related article IDs not present in the provided source articles
  - normalizes string arrays
  - converts `YYYY-MM-DD` timeline dates when present
- Populated `TopicBriefEvidence` source metadata from local articles and feeds instead of trusting AI for titles, source names, URLs, or published dates.
- Added `TopicBriefGenerationUseCase` in `RSSRadarProcessing` as the repository-backed generation and cache boundary.
- Implemented cache-first behavior: if `(topic_id, brief_type)` already exists, `generateIfNeeded(...)` returns the cached `TopicBrief` without calling AI again.
- Enforced Step 25 topic/brief rules:
  - active topics can generate only full briefs
  - candidate topics can generate only preview briefs
  - ignored and archived topics are rejected for TopicBrief generation
- Wired `ProcessingEngineExecutor` to execute `generate_topic_brief` jobs when a `TopicBriefGenerating` implementation is explicitly injected.
- Split `ProcessingEngineExecutor` into its own file to keep `ProcessingEngine.swift` focused on queue scheduling and retry state transitions.
- Added AI tests and fixture:
  - `Tests/RSSRadarAITests/Fixtures/topic-brief.json`
  - `TopicBriefGenerationServiceTests`
- Added processing integration tests:
  - active full brief generation and cache reuse
  - candidate preview-only enforcement
  - `generate_topic_brief` job execution through `ProcessingEngineExecutor`
- Kept Step 26 out of scope:
  - no manual regenerate failure-protection workflow
  - no explicit "preserve old brief on failed regeneration" behavior
  - no UI error display for regeneration failures

Verification:

- User verified this step after local testing.
- `swift test --filter RSSRadarAITests` passed with 22 tests and 0 failures.
- `swift test --filter RSSRadarProcessingTests` passed with 34 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 80 Swift files.
- `swift test` passed with 133 tests and 0 failures.

Stop point: next step is implementation-plan Step 26, implement TopicBrief failure protection. Do not start Step 26 until explicitly requested.

## 2026-05-21 - Step 26: TopicBrief failure protection

Completed implementation-plan Step 26.

- Added an explicit manual regeneration path to `TopicBriefGenerationUseCase`:
  - `generateIfNeeded(...)` remains cache-first and continues to avoid unnecessary AI calls.
  - `regenerate(...)` bypasses the cache for user-triggered regeneration.
- Preserved old TopicBrief cache on regeneration failure:
  - the use case only writes the newly generated brief after the generator returns successfully.
  - if AI generation or validation throws, the existing `(topic_id, brief_type)` cache remains unchanged.
- Added failure logging for manual regeneration:
  - failed manual regeneration writes an error-level `operation_logs` row.
  - log context records only non-sensitive identifiers: `topic_id` and `brief_type`.
  - the original error is rethrown so later UI code can display the failure.
- Kept Step 27 out of scope:
  - no Today page data source
  - no topic ranking score
  - no aggregation of scan status, important topics, candidate topics, or active topic updates

Verification:

- User verified this step after local testing.
- `swift test --filter TopicBriefGenerationUseCaseTests` passed with 4 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 80 Swift files.
- `swift test` passed with 134 tests and 0 failures.

Stop point: next step is implementation-plan Step 27, implement Today page data source. Do not start Step 27 until explicitly requested.

## 2026-05-21 - Step 27: Today page data source

Completed implementation-plan Step 27.

- Added `TodayPageDataSource` in `RSSRadarProcessing` as the use-case/data-source boundary for the Today page.
- Implemented Today snapshot aggregation:
  - scan status from feeds, processing jobs, articles, and recent operation logs
  - today's important topics from `active` topics only
  - new candidate topics from `candidate` topics only
  - tracked topic updates from active topics with today's new relationships or latest changes
- Implemented the documented topic ranking inputs:
  - recency
  - topic importance
  - today's new article count
  - active topic bonus
- Added stable sorting tie-breakers by score, latest activity, topic name, and topic ID so Today ordering remains deterministic.
- Included compact Today topic fields for later UI work:
  - topic
  - cached full/preview brief when available
  - current takeaway
  - latest changes
  - new and total related article counts
  - primary source names
  - latest activity timestamp
  - ranking score
- Kept Step 28 out of scope:
  - no Topic Detail data source
  - no Topic Detail article/evidence expansion
  - no UI wiring

Verification:

- User verified this step after local testing.
- `swift test --filter TodayPageDataSourceTests` passed with 3 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 82 Swift files.
- `swift test` passed with 137 tests and 0 failures.

Stop point: next step is implementation-plan Step 28, implement Topic Detail data source. Do not start Step 28 until explicitly requested.

## 2026-05-21 - Step 28: Topic Detail data source

Completed implementation-plan Step 28.

- Added `TopicDetailDataSource` in `RSSRadarProcessing` as the use-case/data-source boundary for Topic Detail.
- Implemented Topic Detail snapshot aggregation:
  - topic title and status through the full `Topic`
  - cached `TopicBrief` content for current takeaway, latest changes, timeline, viewpoints, evidence, questions to watch, and related article IDs
  - evidence expansion back to local source article, source feed name, article analysis summary, and topic contribution type
  - related article rows with title, source name, published date, AI summary, contribution type, relationship reason, confidence, and original URL
- Added default brief selection for Topic Detail:
  - candidate topics default to preview brief
  - other topic statuses default to full brief
- Kept the data source read-only:
  - no AI generation
  - no TopicBrief regeneration
  - no scan or processing job creation
  - no Markdown rendering or export behavior
- Added Topic Detail integration tests using temporary SQLite databases and full TopicBrief fixtures.
- Kept Step 29 out of scope:
  - no Markdown copy
  - no Markdown file export
  - no export renderer

Verification:

- User verified this step after local testing.
- `swift test --filter TopicDetailDataSourceTests` passed with 4 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 84 Swift files.
- `swift test` passed with 141 tests and 0 failures.

Stop point: next step is implementation-plan Step 29, implement Markdown copy and file export. Do not start Step 29 until explicitly requested.

## 2026-05-21 - Step 29: Markdown copy and file export

Completed implementation-plan Step 29.

- Added a dedicated `RSSRadarExport` library target to keep Markdown rendering and export behavior out of UI, Processing, Persistence, Feeds, and AI modules.
- Added `TopicBriefMarkdownRenderer` to render a `TopicDetailSnapshot` into Markdown for the current topic.
- Markdown output includes the required Step 29 sections:
  - topic name
  - generated time
  - current takeaway
  - latest changes
  - timeline
  - viewpoints
  - evidence with source article links
  - questions to watch
  - related article links with source, published time, contribution type, and AI summary when available
- Added `TopicBriefMarkdownExportService` to support:
  - copying rendered Markdown through an injectable clipboard boundary
  - exporting the current topic as one `.md` file
- Added `SystemMarkdownClipboardWriter` using macOS `NSPasteboard` for the real clipboard implementation.
- Kept file export intentionally narrow:
  - `.md` file paths only
  - no PDF export
  - no Notion sync
  - no Obsidian sync
  - no folder auto-sync
- Added `RSSRadarExportTests` with fixed TopicBrief and Article data to verify Markdown rendering, clipboard boundary behavior, file writing, missing-cache errors, and non-`.md` path rejection.
- Did not implement Step 30:
  - no Onboarding flow
  - no UI wiring for copy/export buttons
  - no OPML/manual add onboarding screens
  - no AI Provider setup UI
  - no first-scan onboarding flow

Verification:

- User verified this step after local testing.
- `swift test --filter RSSRadarExportTests` passed with 5 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 88 Swift files.
- `swift test` passed with 146 tests and 0 failures.

Stop point: next step is implementation-plan Step 30, implement Onboarding flow. Do not start Step 30 until explicitly requested.

## 2026-05-21 - Step 30: Onboarding flow

Completed implementation-plan Step 30.

- Added app runtime bootstrap with `AppEnvironment`:
  - creates the default local SQLite database path under Application Support
  - runs database migrations
  - wires repositories, Keychain storage, feed import use cases, processing engine, and candidate topic management use case
- Updated the SwiftUI app entry so startup failures show a small error view instead of crashing silently.
- Updated the root view so first launch shows onboarding through `@AppStorage("hasCompletedOnboarding")`; after completion it returns to the existing app shell.
- Added `OnboardingViewModel` as the Step 30 orchestration boundary:
  - loads existing settings and feed/candidate summaries
  - adds a manual RSS feed through `ManualFeedAddUseCase`
  - imports OPML through `OPMLImportUseCase`
  - saves AI provider/base URL/model/settings through `AppSettingsRepository`
  - saves API Key only to macOS Keychain and persists only the Keychain account identifier
  - starts the first scan through `ProcessingEngine`
  - analyzes parsed articles through `ArticleAnalysisUseCase`
  - assigns analyzed articles to topics through `TopicAssignmentUseCase`
  - refreshes candidate topic previews through `CandidateTopicManagementUseCase`
- Added `OnboardingView` with the documented first-use flow:
  - welcome/local-first explanation
  - manual RSS URL add
  - OPML import file picker
  - AI Provider segmented picker, base URL, model and secure API Key field
  - article processing limit stepper
  - first scan button
  - candidate topic preview section
- Styled the onboarding screen using the repository `DESIGN.md` reference:
  - warm cream canvas
  - deep green hero band
  - green pill buttons
  - white soft-shadow cards
  - floating circular continue button
- Kept Step 31 out of scope:
  - no full Feeds page
  - no full Processing page
  - no full Settings page
  - no clear-local-data UI
  - no failed-job management UI

Verification:

- User verified this step after local testing.
- `swift test` passed with 146 tests and 0 failures.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 91 Swift files.

Stop point: next step is implementation-plan Step 31, implement Feeds, Processing, and Settings pages. Do not start Step 31 until explicitly requested.

## 2026-05-21 - Step 31: Feeds, Processing, and Settings pages

Completed implementation-plan Step 31.

- Added full app-shell pages for Feeds, Processing, and Settings, replacing the Step 30 placeholders while leaving Today and Topics unchanged.
- Added shared app UI support:
  - `AppTheme` for the warm cream, green, pill-button, card, and status-banner styling used by Step 31 pages.
  - `AppFormatting` for compact date display helpers.
  - `AppViewModelSupport` for shared user-facing error text and enum display names.
- Added `FeedsViewModel` and `FeedsView`:
  - lists saved feeds with status, scan timestamps, progress, and last error.
  - supports manual RSS add through `ManualFeedAddUseCase`.
  - supports OPML import through `OPMLImportUseCase`.
  - supports per-feed refresh and refresh-all through `ProcessingEngine`.
  - supports pause/resume by updating feed status through `FeedRepository`.
  - supports feed deletion through `FeedRepository`, relying on SQLite foreign-key cascades for related feed data.
- Added `ProcessingViewModel` and `ProcessingView`:
  - shows pending/running/failed/completed counts.
  - lists processing jobs with status, scheduled time, attempt count, and failure reason.
  - shows recent user-visible `operation_logs`.
  - supports running pending jobs and retrying failed jobs through `ProcessingEngine`.
- Added `SettingsViewModel` and `SettingsView`:
  - loads and saves AI provider, base URL, model, scan mode, scan interval, processing limits, AI timeout, and database path through `AppSettingsRepository`.
  - saves API Key only to macOS Keychain and persists only the Keychain account identifier.
  - supports deleting the saved Keychain API Key.
  - provides a conservative clear-local-data sheet requiring the user to type `CLEAR`.
  - clear-local-data deletes business data by repository APIs and keeps the Keychain API Key by default.
  - deleting the Keychain API Key during clear-local-data only happens when the user explicitly toggles that option.
- Added `UserCorrectionRepository.delete(id:)` so the Settings clear-local-data path can remove `user_corrections` along with feeds, articles, topics, jobs, and logs.
- Kept Step 32 out of scope:
  - no dedicated no-RSS-source state.
  - no dedicated missing-API-key state.
  - no dedicated AI-call-failed state.
  - no dedicated content-fetch-failed state.
  - no dedicated no-new-articles state.

Verification:

- User verified this step after local testing.
- `swift build` passed.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 100 Swift files.
- `swift test` passed with 146 tests and 0 failures.

Stop point: next step is implementation-plan Step 32, implement errors and empty states. Do not start Step 32 until explicitly requested.

## 2026-05-22 - Step 32: Errors and empty states

Completed implementation-plan Step 32.

- Added dedicated empty/error state handling across the existing Step 31 app-shell pages.
- Added `EmptyStateCard` to `AppTheme` as the shared warm-cream/green/soft-card empty state surface for actionable guidance.
- Updated `FeedsViewModel` and `FeedsView`:
  - keeps a per-feed article snapshot so the UI can explain RSS summary fallback.
  - shows a no-RSS-source state with OPML import as the primary next action.
  - disables refresh-all when there are no feeds.
  - reports no-new-article scans after single-feed and all-feed refreshes.
  - shows `no_articles` feed status as a non-blocking feed-level state.
  - shows a content extraction fallback notice when persisted articles use `content_source = rss_summary`.
- Updated `ProcessingViewModel` and `ProcessingView`:
  - reads whether an API Key account identifier is saved in `AppSettings`.
  - classifies failed AI jobs (`analyze_article`, `assign_topics`, `generate_topic_brief`) for a dedicated AI failure state.
  - shows missing-API-key guidance while making clear RSS feed scanning can continue.
  - shows AI call failures with failure reason, model name when available, failure time, retry action, and Settings action.
  - shows empty states for no processing jobs and no operation logs instead of blank sections.
- Updated `SettingsView`:
  - shows a dedicated missing API Key notice in the AI settings card.
  - explains that RSS scanning can continue, while article analysis, topic generation, and TopicBrief generation require a saved provider/model/API Key.
- Updated `AppRootView` so Processing can route the user directly to Settings from the missing-key and AI-failure states.
- Did not start Step 33:
  - no privacy/security acceptance scan was performed.
  - no telemetry/dependency audit was added.
  - no database/log/export secret scan was added.

Verification:

- User verified this step after local testing.
- `swift build` passed.
- `make verify` passed and ran SwiftLint plus `swift test`.
- SwiftLint reported 0 violations across 100 Swift files.
- `swift test` passed with 146 tests and 0 failures.

Stop point: next step is implementation-plan Step 33, execute privacy and security acceptance. Do not start Step 33 until explicitly requested.

## 2026-05-22 - Step 33: Privacy and security acceptance

Completed implementation-plan Step 33.

- Audited the implemented code and package manifests for privacy-sensitive integration points:
  - no developer-hosted server or AI proxy endpoint was added.
  - no cloud sync, telemetry, analytics, cloud logging, crash-reporting SDK, or extra third-party dependency was added.
  - AI network requests remain limited to `URLSessionAIProvider`, which sends requests from the user's Mac to the user-configured OpenAI-compatible, Anthropic, or Custom provider.
  - RSS/article network requests remain limited to feed/article URLs supplied by the user's sources.
- Added a repeatable privacy/security audit command:
  - `Scripts/privacy_security_audit.sh`
  - `make privacy-audit`
- Updated `make verify` so future verification runs SwiftLint, the privacy/security audit, and the full test suite.
- The audit checks package manifests and source/test imports for telemetry references, hard-coded unexpected endpoints, and API-key/auth-looking plaintext in prompts, fixtures, log files, Markdown export-like files, and repository database files.
- Added `SensitiveContentValidator` in the persistence module and reused it for user-visible operation logs.
- Hardened `ProcessingJobRepository` so `processing_jobs.payload` keys/values and persisted job error messages reject obvious API key or authorization markers before they can be written to SQLite.
- Added repository tests confirming processing job payloads and job error messages reject API key / Authorization / Bearer / `x-api-key` marker content.
- Kept Step 34 out of scope:
  - no performance/stability benchmark was performed.
  - no large RSS corpus or UI responsiveness profiling was added.
  - no startup timing measurement was added.

Verification:

- User verified this step after local testing.
- `Scripts/privacy_security_audit.sh` passed.
- `swift test --filter RSSRadarPersistenceTests` passed with 32 tests and 0 failures.
- `make verify` passed and ran SwiftLint, privacy audit, and `swift test`.
- SwiftLint reported 0 violations across 101 Swift files.
- Privacy audit passed.
- `swift test` passed with 147 tests and 0 failures.

Stop point: next step is implementation-plan Step 34, execute performance and stability acceptance. Do not start Step 34 until explicitly requested.

## 2026-05-22 - Step 34: Performance and stability acceptance

Completed implementation-plan Step 34.

- Added `ProcessingStartupRecoveryUseCase` as the app-bootstrap recovery boundary. It calls `ProcessingJobRepository.recoverInterruptedJobs` and writes a warning-level operation log when at least one interrupted job is recovered. `AppEnvironment.make()` now calls it after database migration and before running pending jobs.
- Optimized repository query paths for large data sets:
  - `ArticleRepository.fetchGroupedByFeedID()` returns `OrderedDictionary<feed_id, [article]>` in a single pass without N+1 article fetches.
  - `ArticleRepository.fetch(ids:)` allows batch article lookup by ID without loading all articles.
  - `ArticleRepository` article count queries use `SELECT COUNT(*) WHERE feed_id = ?` without decoding full article objects.
  - `TopicArticleRepository.fetchAll()` returns flat arrays for in-memory relationship grouping rather than one query per topic.
  - `TopicBriefRepository.fetchAll()` returns flat arrays without per-topic subqueries.
  - `TodayPageDataSource` avoids N+1 lookups by preloading article analyses, briefs, and topic relations in bulk before snapshot aggregation.
- `FeedsViewModel` switched to batch article group snapshot for feed-level article counts, replacing per-feed article list decoding.
- Added `PerformanceStabilityAcceptanceTests` covering:
  - startup bootstrap, migration, repository creation, and recovery path fits the 2-second budget on a 60-feed / 3000-article / 290-job data set.
  - feeds and processing page list snapshots remain responsive (< 2s) on a large local data set.
  - today page snapshot aggregation remains responsive (< 2s) on a large local data set.
  - a bounded processing run executes a per-type concurrent slice quickly enough for UI to stay usable; one failing job does not block the remaining queue.
  - interrupted running jobs recover and re-execute without repeating already-completed jobs.
- Added `make performance-stability` and `Scripts/performance_stability_acceptance.sh` as the local performance acceptance entry point, aligned with the Step 33 `make privacy-audit` pattern.

Verification:

- User verified this step after local testing.
- `swift test --filter PerformanceStabilityAcceptanceTests` passed with 5 tests and 0 failures (8.1s total).
- `Scripts/performance_stability_acceptance.sh` passed.
- `make verify` passed and ran SwiftLint, privacy audit, and `swift test`.
- SwiftLint reported 0 violations across 103 Swift files.
- Privacy audit passed.
- `swift test` passed with 152 tests and 0 failures.

Stop point: implementation-plan Step 34 complete. Next step is implementation-plan Step 35, execute MVP end-to-end acceptance.

## 2026-05-22 - Step 35: MVP end-to-end acceptance

Completed implementation-plan Step 35.

- Added `MVPEndToEndAcceptanceTests` as the full MVP acceptance test. Starting from an empty SQLite database, it exercises the complete closed loop: RSS/OPML import, Provider/Keychain configuration, first scan, AI retry with attempt counting, article analysis, topic generation, multi-topic assignment, candidate preview, track/ignore/rename/edit-description, active topic continuous update, full TopicBrief generation, Topic Detail snapshot, and Markdown copy and file export.
- Added `Scripts/mvp_end_to_end_acceptance.sh` as the dedicated Step 35 acceptance entry point, aligned with the Step 33 `make privacy-audit` and Step 34 `make performance-stability` patterns.
- Added `make mvp-e2e` to the Makefile, calling `Scripts/mvp_end_to_end_acceptance.sh`.
- Updated `Package.swift` so `RSSRadarProcessingTests` can import `RSSRadarExport`, enabling the Markdown export closure to be covered by the end-to-end acceptance test.

Verification:

- User verified this step after local testing.
- `swift test --filter MVPEndToEndAcceptanceTests` passed with 1 test and 0 failures (0.704s).
- `Scripts/mvp_end_to_end_acceptance.sh` passed.
- `make verify` passed and ran SwiftLint, privacy audit, and `swift test`.
- SwiftLint reported 0 violations across 103 Swift files.
- Privacy audit passed.
- `swift test` passed with 153 tests and 0 failures.

Stop point: implementation-plan Step 35 complete. MVP 35-step implementation is complete.

## 2026-05-22 - Navigation sidebar selection fix

Completed a focused post-MVP UI iteration for the main app shell.

- Fixed the macOS `NavigationSplitView` sidebar so Today, Topics, Feeds, Processing, and Settings are real selectable rows.
- Changed `AppRootView` from `List(RSSRadarSection.allCases, selection:)` with plain labels to an explicit `List(selection:)` containing `ForEach` rows tagged with their `RSSRadarSection`.
- Updated `RSSRadarSection` to conform to `Hashable`, matching SwiftUI's selection/tag requirements.
- Kept page structure unchanged: Today and Topics remain placeholders; Feeds, Processing, and Settings continue to use their existing ViewModels.

Verification:

- `swift build` passed.

## 2026-05-22 - Post-scan AI processing pipeline

Completed a focused queue orchestration iteration after RSS scan verification.

- Added `ProcessingEngine.enqueueArticleAnalysis(...)` and `enqueueParsedArticleAnalysis(...)` so parsed articles can be queued for durable AI analysis without duplicate analysis jobs.
- Added `ProcessingEngine.runPendingJobsUntilIdle(maxPasses:)` so UI-triggered refreshes can advance feed scan, article analysis, and topic assignment until the current ready queue is empty.
- Updated `ProcessingEngineExecutor`:
  - `fetch_feed` now queues `analyze_article` jobs for newly parsed articles when AI settings are available.
  - `analyze_article` now queues an `assign_topics` job after analysis is persisted.
  - dynamic AI provider/settings closures allow production execution to use current Settings + Keychain without storing API keys in SQLite or job payloads.
- Updated `AppEnvironment` to inject the dynamic AI provider factory and AI settings provider into the production processing executor.
- Updated `FeedsViewModel` so single-feed and all-feed refreshes also enqueue existing `parsed` articles before scanning, covering articles parsed before this pipeline existed.
- Added `ProcessingEngineTests.testDefaultExecutorPipelinesFeedScanIntoAnalysisAndTopicAssignment` to cover the feed scan -> analysis -> topic assignment queue chain.

Verification:

- `swift test --filter ProcessingEngineTests` passed with 9 tests and 0 failures.
- `swift test` passed with 154 tests and 0 failures.

## 2026-05-22 - Article analysis failure state consistency

Completed a focused queue state consistency fix.

- Changed `ProcessingEngine` so every exhausted `analyze_article` job failure marks the related `Article` as `failed` and persists the final error message.
- Previously only `ArticleAnalysisValidationError` exhausted failures updated the article status; provider-level failures such as missing assistant content could leave articles stuck in `parsed` after all retries failed.
- Added `ProcessingEngineTests.testExhaustedArticleAnalysisProviderFailureMarksArticleFailedWithoutAnalysis` to cover provider response failures.

Verification:

- `swift test --filter ProcessingEngineTests` passed with 10 tests and 0 failures.
- `swift test` passed with 155 tests and 0 failures.

## 2026-05-28 - UI optimization pass

Completed the requested UI optimization from `UI优化.md`.

- Added app icon resources from `icon.png` under `RSSRadarApp/Resources` and set the runtime macOS application icon during app initialization.
- Removed the Today entry from the main sidebar; the app now opens on `主题聚合`.
- Localized visible app shell, onboarding, topics, feeds, processing, settings, status labels, and primary action text to Chinese.
- Updated Topics:
  - added the requested explanatory copy above the status filter.
  - renamed statuses to `全部`、`待确认主题`、`跟踪主题`、`忽略主题`.
  - removed archived status from the visible filter and default visible topic list.
  - changed candidate actions to `跟踪` and `忽略`.
- Updated Feeds:
  - split the page into “添加源” and “当前源管理”.
  - renamed refresh/delete actions to `手动刷新` and `删除`.
  - removed the pause/resume button from feed rows.
- Updated Settings:
  - split AI settings into an upper “AI 新配置” input area and lower “当前配置” read-only area.
  - current configuration explicitly shows URL and Model.
- During verification, `ArticleAnalysisService` prompt content budget was temporarily restored to the then-documented/tested 24,000 characters; this was later superseded by the explicit 100,000-character budget.

Verification:

- `swift build` passed.
- `make verify` passed: SwiftLint, privacy/security audit, and `swift test` all passed.

## 2026-05-28 - Article analysis prompt budget increase

Completed a focused AI prompt budget update.

- Changed `ArticleAnalysisService` article content prompt budget from 24,000 characters to 100,000 characters.
- Updated `ArticleAnalysisServiceTests.testAnalyzeArticleTruncatesLongContentBeforePrompting` to use a 120,000-character article and assert truncation at 100,000 characters.
- Updated architecture and progress documentation to reflect the 100,000-character budget.

Verification:

- `swift test --filter ArticleAnalysisServiceTests/testAnalyzeArticleTruncatesLongContentBeforePrompting` passed.
- `make verify` passed: SwiftLint, privacy/security audit, and `swift test` all passed.
