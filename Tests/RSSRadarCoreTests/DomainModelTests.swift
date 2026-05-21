import XCTest
@testable import RSSRadarCore

final class DomainModelTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testPackageSkeletonLoadsCoreModule() {
        XCTAssertEqual(RSSRadarCore.moduleName, "RSSRadarCore")
    }

    func testFeedDefaultsAndRoundTripCoding() throws {
        let feed = Feed(
            id: "feed-id",
            title: "Example Feed",
            url: try XCTUnwrap(URL(string: "https://example.com/rss.xml")),
            siteURL: try XCTUnwrap(URL(string: "https://example.com")),
            lastCheckedAt: fixedDate,
            errorMessage: "Temporary error",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(feed.status, .active)
        XCTAssertEqual(feed.errorMessage, "Temporary error")
        XCTAssertEqual(try roundTrip(feed), feed)
        XCTAssertEncodedKeys(feed, contain: ["site_url", "last_checked_at", "error_message"])
    }

    func testArticleDefaultsAndRoundTripCoding() throws {
        let article = Article(
            id: "article-id",
            feedID: "feed-id",
            title: "Article",
            url: try XCTUnwrap(URL(string: "https://example.com/article")),
            publishedAt: fixedDate,
            rssSummary: "Summary",
            content: "Content",
            contentSource: .rssFullContent,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(article.status, .fetched)
        XCTAssertEqual(article.contentSource, .rssFullContent)
        XCTAssertEqual(try roundTrip(article), article)
        XCTAssertEncodedKeys(article, contain: ["feed_id", "published_at", "content_source"])
    }

    func testArticleAnalysisDefaultsAndRoundTripCoding() throws {
        let analysis = ArticleAnalysis(
            id: "analysis-id",
            articleID: "article-id",
            summary: "Summary",
            contentType: .analysis,
            importanceScore: 0.8,
            modelName: "model",
            generatedAt: fixedDate
        )

        XCTAssertEqual(analysis.keyPoints, [])
        XCTAssertEqual(analysis.entities, [])
        XCTAssertEqual(analysis.possibleTopics, [])
        XCTAssertEqual(try roundTrip(analysis), analysis)
        XCTAssertEncodedKeys(analysis, contain: ["article_id", "key_points", "content_type"])
    }

    func testTopicDefaultsAndRoundTripCoding() throws {
        let topic = Topic(
            id: "topic-id",
            name: "Claude Code 在大型代码库中的表现",
            description: "跟踪 Claude Code 对大型代码库任务的处理能力。",
            originalAIName: "Claude Code 表现",
            originalAIDescription: "AI 生成描述",
            importanceScore: 0.7,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(topic.status, .candidate)
        XCTAssertEqual(topic.entities, [])
        XCTAssertEqual(try roundTrip(topic), topic)
        XCTAssertEncodedKeys(topic, contain: ["original_ai_name", "importance_score"])
    }

    func testTopicArticleRoundTripCoding() throws {
        let topicArticle = TopicArticle(
            topicID: "topic-id",
            articleID: "article-id",
            confidence: 0.87,
            reason: "Relevant",
            contributionType: .newEvent,
            createdAt: fixedDate
        )

        XCTAssertEqual(try roundTrip(topicArticle), topicArticle)
        XCTAssertEncodedKeys(topicArticle, contain: ["topic_id", "article_id", "contribution_type"])
    }

    func testTopicBriefDefaultsAndRoundTripCoding() throws {
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let brief = TopicBrief(
            id: "brief-id",
            topicID: "topic-id",
            briefType: .full,
            currentTakeaway: "Current takeaway",
            latestChanges: [TopicBriefChange(text: "Changed", articleIDs: ["article-id"])],
            timeline: [
                TopicBriefTimelineItem(
                    date: fixedDate,
                    title: "Milestone",
                    description: "Description",
                    articleIDs: ["article-id"]
                )
            ],
            viewpoints: [TopicBriefViewpoint(title: "View", summary: "Summary", articleIDs: ["article-id"])],
            evidence: [
                TopicBriefEvidence(
                    content: "Evidence",
                    sourceArticleID: "article-id",
                    sourceArticleTitle: "Article",
                    sourceName: "Example",
                    sourceURL: sourceURL,
                    publishedAt: fixedDate
                )
            ],
            questionsToWatch: ["Question"],
            relatedArticleIDs: ["article-id"],
            modelName: "model",
            generatedAt: fixedDate
        )

        XCTAssertEqual(try roundTrip(brief), brief)
        XCTAssertEncodedKeys(brief, contain: ["brief_type", "current_takeaway", "related_article_ids"])
    }

    func testAppSettingsDefaultsAndRoundTripCoding() throws {
        let settings = AppSettings()

        XCTAssertEqual(settings.aiProvider, .openAICompatible)
        XCTAssertEqual(settings.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(settings.scanMode, .manual)
        XCTAssertEqual(settings.scanIntervalHours, 6)
        XCTAssertEqual(settings.maxArticlesPerScan, 100)
        XCTAssertEqual(settings.maxArticlesForNewFeed, 20)
        XCTAssertEqual(settings.maxArticlesPerTopicBatch, 20)
        XCTAssertEqual(settings.aiRequestTimeoutSeconds, 60)
        XCTAssertNil(settings.keychainAccountIdentifier)
        XCTAssertEqual(try roundTrip(settings), settings)
        XCTAssertEncodedKeys(settings, contain: ["ai_provider", "base_url", "scan_mode"])
    }

    func testProcessingJobDefaultsAndRoundTripCoding() throws {
        let job = ProcessingJob(
            id: "job-id",
            jobType: .analyzeArticle,
            entityType: .article,
            entityID: "article-id",
            payload: ["source": "scan"],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        XCTAssertEqual(job.status, .pending)
        XCTAssertEqual(job.attemptCount, 0)
        XCTAssertEqual(job.maxAttempts, 3)
        XCTAssertEqual(try roundTrip(job), job)
        XCTAssertEncodedKeys(job, contain: ["job_type", "entity_type", "attempt_count"])
    }

    func testOperationLogDefaultsAndRoundTripCoding() throws {
        let log = OperationLog(
            id: "log-id",
            level: .info,
            message: "Feed scan completed",
            context: ["feed_id": "feed-id"],
            createdAt: fixedDate
        )

        XCTAssertEqual(try roundTrip(log), log)
        XCTAssertEncodedKeys(log, contain: ["created_at", "context"])
    }

    func testGeneratedIDsAreUUIDStrings() throws {
        let feed = Feed(title: "Example", url: try XCTUnwrap(URL(string: "https://example.com/rss.xml")))
        let topic = Topic(name: "Topic", description: "Description")

        XCTAssertNotNil(UUID(uuidString: feed.id))
        XCTAssertNotNil(UUID(uuidString: topic.id))
    }
}

private extension DomainModelTests {
    func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    func XCTAssertEncodedKeys<Value: Encodable>(
        _ value: Value,
        contain expectedKeys: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let data = try? JSONEncoder().encode(value)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        for key in expectedKeys {
            XCTAssertTrue(json.contains("\"\(key)\""), "Missing encoded key \(key)", file: file, line: line)
        }
    }
}
