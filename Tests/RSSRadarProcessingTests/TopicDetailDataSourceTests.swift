import Foundation
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class TopicDetailDataSourceTests: XCTestCase {
    func testTopicDetailLoadsFullBriefEvidenceAndRelatedArticles() throws {
        let repositories = try makeTopicDetailRepositories()
        try seedTopicDetailGraph(topicStatus: .active, repositories: repositories)
        let dataSource = TopicDetailDataSource(repositories: repositories)

        let snapshot = try dataSource.load(topicID: "topic-detail")

        XCTAssertEqual(snapshot.topic.name, "Claude Code performance in large Swift codebases")
        XCTAssertEqual(snapshot.briefType, .full)
        XCTAssertEqual(snapshot.currentTakeaway, "Claude Code is becoming more useful for large Swift refactors.")
        XCTAssertEqual(snapshot.latestChanges.map(\.text), ["Teams reported better multi-file edit reliability."])
        XCTAssertEqual(snapshot.timeline.map(\.title), ["Pilot expanded"])
        XCTAssertEqual(snapshot.viewpoints.map(\.title), ["Optimistic teams"])
        XCTAssertEqual(snapshot.questionsToWatch, ["Whether gains persist after onboarding."])

        let evidence = try XCTUnwrap(snapshot.evidence.first)
        XCTAssertEqual(evidence.evidence.content, "The pilot reported 30% faster setup.")
        XCTAssertEqual(evidence.sourceArticle?.id, "article-main")
        XCTAssertEqual(evidence.sourceArticle?.title, "Claude Code adoption update")
        XCTAssertEqual(evidence.sourceName, "Engineering Blog")
        XCTAssertEqual(evidence.analysisSummary, "Claude Code adoption improved in a large Swift codebase.")
        XCTAssertEqual(evidence.contributionType, .newData)

        XCTAssertEqual(snapshot.relatedArticles.map(\.article.id), ["article-main", "article-extra"])
        XCTAssertEqual(snapshot.relatedArticles[0].article.title, "Claude Code adoption update")
        XCTAssertEqual(snapshot.relatedArticles[0].sourceName, "Engineering Blog")
        XCTAssertEqual(snapshot.relatedArticles[0].article.publishedAt, topicDetailDate)
        XCTAssertEqual(
            snapshot.relatedArticles[0].analysisSummary,
            "Claude Code adoption improved in a large Swift codebase."
        )
        XCTAssertEqual(snapshot.relatedArticles[0].contributionType, .newData)
        XCTAssertEqual(snapshot.relatedArticles[0].article.url, URL(string: "https://example.com/article-main")!)
        XCTAssertEqual(snapshot.relatedArticles[1].contributionType, .newOpinion)
    }

    func testTopicDetailDefaultsCandidateTopicsToPreviewBrief() throws {
        let repositories = try makeTopicDetailRepositories()
        try seedTopicDetailGraph(topicStatus: .candidate, repositories: repositories)
        let dataSource = TopicDetailDataSource(repositories: repositories)

        let snapshot = try dataSource.load(topicID: "topic-detail")

        XCTAssertEqual(snapshot.briefType, .preview)
        XCTAssertEqual(snapshot.brief?.briefType, .preview)
        XCTAssertEqual(snapshot.currentTakeaway, "Candidate preview takeaway.")
    }

    func testTopicDetailReturnsEmptyBriefSectionsWhenCacheIsMissing() throws {
        let repositories = try makeTopicDetailRepositories()
        let topic = Topic(
            id: "topic-without-brief",
            name: "Topic without brief",
            description: "No cached brief yet.",
            status: .active,
            createdAt: topicDetailDate,
            updatedAt: topicDetailDate
        )
        try repositories.topics.save(topic)
        let dataSource = TopicDetailDataSource(repositories: repositories)

        let snapshot = try dataSource.load(topicID: topic.id)

        XCTAssertNil(snapshot.brief)
        XCTAssertNil(snapshot.currentTakeaway)
        XCTAssertTrue(snapshot.latestChanges.isEmpty)
        XCTAssertTrue(snapshot.timeline.isEmpty)
        XCTAssertTrue(snapshot.viewpoints.isEmpty)
        XCTAssertTrue(snapshot.evidence.isEmpty)
        XCTAssertTrue(snapshot.questionsToWatch.isEmpty)
        XCTAssertTrue(snapshot.relatedArticles.isEmpty)
    }

    func testTopicDetailThrowsForMissingTopic() throws {
        let repositories = try makeTopicDetailRepositories()
        let dataSource = TopicDetailDataSource(repositories: repositories)

        XCTAssertThrowsError(try dataSource.load(topicID: "missing-topic")) { error in
            XCTAssertEqual(error as? TopicDetailDataSourceError, .topicNotFound("missing-topic"))
        }
    }
}

private func makeTopicDetailRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarTopicDetailDataSourceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private func seedTopicDetailGraph(topicStatus: TopicStatus, repositories: RSSRadarRepositories) throws {
    let feed = topicDetailFeed()
    let topic = topicDetailTopic(status: topicStatus)
    let mainArticle = makeTopicDetailArticle(
        id: "article-main",
        feedID: feed.id,
        title: "Claude Code adoption update",
        publishedAt: topicDetailDate
    )
    let extraArticle = makeTopicDetailArticle(
        id: "article-extra",
        feedID: feed.id,
        title: "Developers debate AI refactoring",
        publishedAt: topicDetailDate.addingTimeInterval(-3_600)
    )

    try repositories.feeds.save(feed)
    try repositories.topics.save(topic)
    try repositories.articles.save(mainArticle)
    try repositories.articles.save(extraArticle)
    try repositories.articleAnalyses.save(mainTopicDetailAnalysis(articleID: mainArticle.id))
    try repositories.articleAnalyses.save(extraTopicDetailAnalysis(articleID: extraArticle.id))
    try seedTopicDetailRelationships(topicID: topic.id, repositories: repositories)
    try repositories.topicBriefs.save(fullTopicDetailBrief(topicID: topic.id))
    try repositories.topicBriefs.save(previewTopicDetailBrief(topicID: topic.id))
}

private func topicDetailFeed() -> Feed {
    Feed(
        id: "feed-detail",
        title: "Engineering Blog",
        url: URL(string: "https://example.com/feed.xml")!,
        createdAt: topicDetailDate,
        updatedAt: topicDetailDate
    )
}

private func topicDetailTopic(status: TopicStatus) -> Topic {
    Topic(
        id: "topic-detail",
        name: "Claude Code performance in large Swift codebases",
        description: "Tracks Claude Code behavior on large Swift projects.",
        status: status,
        createdAt: topicDetailDate,
        updatedAt: topicDetailDate
    )
}

private func seedTopicDetailRelationships(topicID: String, repositories: RSSRadarRepositories) throws {
    try repositories.topicArticles.save(
        TopicArticle(
            topicID: topicID,
            articleID: "article-main",
            confidence: 0.93,
            reason: "Provides concrete metrics for the topic.",
            contributionType: .newData,
            createdAt: topicDetailDate
        )
    )
    try repositories.topicArticles.save(
        TopicArticle(
            topicID: topicID,
            articleID: "article-extra",
            confidence: 0.78,
            reason: "Adds a different practitioner viewpoint.",
            contributionType: .newOpinion,
            createdAt: topicDetailDate.addingTimeInterval(-60)
        )
    )
}

private func mainTopicDetailAnalysis(articleID: String) -> ArticleAnalysis {
    ArticleAnalysis(
        articleID: articleID,
        summary: "Claude Code adoption improved in a large Swift codebase.",
        keyPoints: ["Teams adopted AI coding tools for multi-file edits."],
        entities: ["Claude Code", "Swift"],
        claims: ["AI coding tools can speed onboarding."],
        events: ["A team expanded Claude Code usage."],
        metrics: ["30% faster setup"],
        contentType: .analysis,
        possibleTopics: ["Claude Code in large Swift codebases"],
        importanceScore: 0.82,
        modelName: "gpt-test",
        generatedAt: topicDetailDate
    )
}

private func extraTopicDetailAnalysis(articleID: String) -> ArticleAnalysis {
    ArticleAnalysis(
        articleID: articleID,
        summary: "Developers remain split on AI-assisted refactoring quality.",
        contentType: .opinion,
        importanceScore: 0.64,
        modelName: "gpt-test",
        generatedAt: topicDetailDate
    )
}

private func makeTopicDetailArticle(
    id: String,
    feedID: String,
    title: String,
    publishedAt: Date
) -> Article {
    Article(
        id: id,
        feedID: feedID,
        title: title,
        url: URL(string: "https://example.com/\(id)")!,
        publishedAt: publishedAt,
        rssSummary: "RSS summary for \(title).",
        content: "Article content for \(title).",
        status: .assigned,
        importanceScore: 0.80,
        createdAt: publishedAt,
        updatedAt: publishedAt
    )
}

private func fullTopicDetailBrief(topicID: String) -> TopicBrief {
    TopicBrief(
        topicID: topicID,
        briefType: .full,
        currentTakeaway: "Claude Code is becoming more useful for large Swift refactors.",
        latestChanges: [
            TopicBriefChange(text: "Teams reported better multi-file edit reliability.", articleIDs: ["article-main"])
        ],
        timeline: [
            TopicBriefTimelineItem(
                date: topicDetailDate,
                title: "Pilot expanded",
                description: "A Swift team expanded its Claude Code pilot.",
                articleIDs: ["article-main"]
            )
        ],
        viewpoints: [
            TopicBriefViewpoint(
                title: "Optimistic teams",
                summary: "Some teams report faster setup and onboarding.",
                articleIDs: ["article-main"]
            )
        ],
        evidence: [
            TopicBriefEvidence(
                content: "The pilot reported 30% faster setup.",
                sourceArticleID: "article-main",
                sourceArticleTitle: "Claude Code adoption update",
                sourceName: "Engineering Blog",
                sourceURL: URL(string: "https://example.com/article-main")!,
                publishedAt: topicDetailDate
            )
        ],
        questionsToWatch: ["Whether gains persist after onboarding."],
        relatedArticleIDs: ["article-main", "article-extra"],
        modelName: "gpt-test",
        generatedAt: topicDetailDate
    )
}

private func previewTopicDetailBrief(topicID: String) -> TopicBrief {
    TopicBrief(
        topicID: topicID,
        briefType: .preview,
        currentTakeaway: "Candidate preview takeaway.",
        relatedArticleIDs: ["article-main"],
        modelName: "gpt-test",
        generatedAt: topicDetailDate
    )
}

private let topicDetailDate = Date(timeIntervalSince1970: 1_700_200_000)
