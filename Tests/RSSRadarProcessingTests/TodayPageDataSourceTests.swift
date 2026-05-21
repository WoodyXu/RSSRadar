import Foundation
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class TodayPageDataSourceTests: XCTestCase {
    func testTodaySnapshotSeparatesActiveAndCandidateTopics() throws {
        let repositories = try makeTodayRepositories()
        let now = todayBaseDate.addingTimeInterval(12 * 60 * 60)
        let active = try seedTodayTopic(
            id: "active-important",
            status: .active,
            importanceScore: 0.85,
            updatedAt: now.addingTimeInterval(-60),
            repositories: repositories
        )
        let candidate = try seedTodayTopic(
            id: "candidate-new",
            status: .candidate,
            importanceScore: 0.80,
            updatedAt: now.addingTimeInterval(-120),
            repositories: repositories
        )
        let ignored = try seedTodayTopic(
            id: "ignored-topic",
            status: .ignored,
            importanceScore: 1.0,
            updatedAt: now,
            repositories: repositories
        )
        try seedTodayTopic(
            id: "old-active",
            status: .active,
            importanceScore: 1.0,
            updatedAt: todayBaseDate.addingTimeInterval(-60),
            repositories: repositories
        )
        try seedTodayBrief(topicID: active.id, briefType: .full, generatedAt: now, repositories: repositories)
        try seedTodayBrief(topicID: candidate.id, briefType: .preview, generatedAt: now, repositories: repositories)
        try seedTodayBrief(topicID: ignored.id, briefType: .preview, generatedAt: now, repositories: repositories)

        let snapshot = try TodayPageDataSource(repositories: repositories, calendar: todayCalendar).load(now: now)

        XCTAssertEqual(snapshot.importantTopics.map(\.topic.id), [active.id])
        XCTAssertEqual(snapshot.newCandidateTopics.map(\.topic.id), [candidate.id])
        XCTAssertTrue(snapshot.trackedTopicUpdates.allSatisfy { $0.topic.status == .active })
    }

    func testTodayTopicRankingUsesRecencyImportanceNewArticlesAndStableTieBreaker() throws {
        let repositories = try makeTodayRepositories()
        let now = todayBaseDate.addingTimeInterval(12 * 60 * 60)
        let highImportance = try seedTodayTopic(
            id: "topic-b",
            name: "Beta topic",
            status: .active,
            importanceScore: 0.95,
            updatedAt: now.addingTimeInterval(-60 * 60),
            repositories: repositories
        )
        let manyNewArticles = try seedTodayTopic(
            id: "topic-a",
            name: "Alpha topic",
            status: .active,
            importanceScore: 0.60,
            updatedAt: now.addingTimeInterval(-60 * 60),
            repositories: repositories
        )
        let stableTieA = try seedTodayTopic(
            id: "topic-c",
            name: "Same score A",
            status: .active,
            importanceScore: 0.50,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60),
            repositories: repositories
        )
        let stableTieB = try seedTodayTopic(
            id: "topic-d",
            name: "Same score B",
            status: .active,
            importanceScore: 0.50,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60),
            repositories: repositories
        )
        try seedTodayBrief(
            topicID: highImportance.id,
            briefType: .full,
            generatedAt: highImportance.updatedAt,
            repositories: repositories
        )
        try seedTodayBrief(
            topicID: manyNewArticles.id,
            briefType: .full,
            generatedAt: manyNewArticles.updatedAt,
            repositories: repositories
        )
        try seedTodayBrief(topicID: stableTieA.id, briefType: .full, generatedAt: stableTieA.updatedAt, repositories: repositories)
        try seedTodayBrief(topicID: stableTieB.id, briefType: .full, generatedAt: stableTieB.updatedAt, repositories: repositories)
        try seedTodayArticles(topicID: manyNewArticles.id, count: 5, createdAt: now, repositories: repositories)

        let snapshot = try TodayPageDataSource(repositories: repositories, calendar: todayCalendar).load(now: now)

        XCTAssertEqual(snapshot.importantTopics.map(\.topic.id), [
            manyNewArticles.id,
            highImportance.id,
            stableTieA.id,
            stableTieB.id
        ])
        XCTAssertGreaterThan(snapshot.importantTopics[0].score, snapshot.importantTopics[1].score)
        let newArticleItem = try XCTUnwrap(snapshot.importantTopics.first { $0.topic.id == manyNewArticles.id })
        XCTAssertEqual(newArticleItem.newArticleCount, 5)
    }

    func testTodayScanStatusAggregatesFeedsJobsArticlesAndLatestLog() throws {
        let repositories = try makeTodayRepositories()
        let now = todayBaseDate.addingTimeInterval(10 * 60 * 60)
        try seedTodayScanStatusInputs(now: now, repositories: repositories)

        let scanStatus = try TodayPageDataSource(repositories: repositories, calendar: todayCalendar)
            .load(now: now)
            .scanStatus

        XCTAssertEqual(scanStatus.lastScanAt, now.addingTimeInterval(-10))
        XCTAssertEqual(scanStatus.processedArticleCount, 1)
        XCTAssertEqual(scanStatus.failedCount, 2)
        XCTAssertEqual(scanStatus.pendingJobCount, 1)
        XCTAssertEqual(scanStatus.latestLog?.message, "Latest scan event")
    }
}

private func seedTodayScanStatusInputs(now: Date, repositories: RSSRadarRepositories) throws {
    let feed = Feed(
        id: "feed-scan",
        title: "Scan Feed",
        url: URL(string: "https://example.com/feed.xml")!,
        lastCheckedAt: now.addingTimeInterval(-30),
        createdAt: todayBaseDate,
        updatedAt: now
    )
    try repositories.feeds.save(feed)
    try seedTodayStatusArticle(
        id: "processed-article",
        feedID: feed.id,
        status: .assigned,
        now: now,
        repositories: repositories
    )
    try seedTodayStatusArticle(
        id: "failed-article",
        feedID: feed.id,
        status: .failed,
        now: now,
        repositories: repositories
    )
    try repositories.processingJobs.save(
        ProcessingJob(
            id: "failed-job",
            jobType: .analyzeArticle,
            entityType: .article,
            status: .failed,
            scheduledAt: now,
            finishedAt: now.addingTimeInterval(-10),
            createdAt: todayBaseDate,
            updatedAt: now
        )
    )
    try repositories.processingJobs.save(
        ProcessingJob(
            id: "pending-job",
            jobType: .fetchFeed,
            entityType: .feed,
            status: .pending,
            scheduledAt: now,
            createdAt: todayBaseDate,
            updatedAt: now
        )
    )
    try repositories.operationLogs.save(OperationLog(level: .info, message: "Latest scan event", createdAt: now))
}

private func seedTodayStatusArticle(
    id: String,
    feedID: String,
    status: ArticleStatus,
    now: Date,
    repositories: RSSRadarRepositories
) throws {
    let article = Article(
        id: id,
        feedID: feedID,
        title: id,
        url: URL(string: "https://example.com/\(id)")!,
        status: status,
        createdAt: todayBaseDate,
        updatedAt: now
    )
    try repositories.articles.save(article)
}

private func makeTodayRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarTodayPageDataSourceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

@discardableResult
private func seedTodayTopic(
    id: String,
    name: String? = nil,
    status: TopicStatus,
    importanceScore: Double,
    updatedAt: Date,
    repositories: RSSRadarRepositories
) throws -> Topic {
    let topic = Topic(
        id: id,
        name: name ?? id,
        description: "Tracks \(id).",
        status: status,
        importanceScore: importanceScore,
        createdAt: updatedAt,
        updatedAt: updatedAt
    )
    try repositories.topics.save(topic)
    return topic
}

private func seedTodayBrief(
    topicID: String,
    briefType: TopicBriefType,
    generatedAt: Date,
    repositories: RSSRadarRepositories
) throws {
    try repositories.topicBriefs.save(
        TopicBrief(
            topicID: topicID,
            briefType: briefType,
            currentTakeaway: "Takeaway for \(topicID).",
            latestChanges: [TopicBriefChange(text: "Recent change for \(topicID).")],
            modelName: "gpt-test",
            generatedAt: generatedAt
        )
    )
}

private func seedTodayArticles(
    topicID: String,
    count: Int,
    createdAt: Date,
    repositories: RSSRadarRepositories
) throws {
    let feed = Feed(
        id: "feed-\(topicID)",
        title: "Feed \(topicID)",
        url: URL(string: "https://example.com/\(topicID)/feed.xml")!,
        createdAt: todayBaseDate,
        updatedAt: createdAt
    )
    try repositories.feeds.save(feed)

    for index in 0..<count {
        let article = Article(
            id: "\(topicID)-article-\(index)",
            feedID: feed.id,
            title: "Article \(index)",
            url: URL(string: "https://example.com/\(topicID)/\(index)")!,
            status: .assigned,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try repositories.articles.save(article)
        try repositories.topicArticles.save(
            TopicArticle(
                topicID: topicID,
                articleID: article.id,
                confidence: 0.8,
                reason: "New article.",
                contributionType: .newEvent,
                createdAt: createdAt
            )
        )
    }
}

private var todayCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private let todayBaseDate = Date(timeIntervalSince1970: 1_700_092_800)
