import Foundation
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class CandidateTopicManagementUseCaseTests: XCTestCase {
    func testCandidateCanBeTrackedAndIgnored() throws {
        let repositories = try makeCandidateRepositories()
        let tracked = try seedCandidateTopic(id: "candidate-track", repositories: repositories)
        let ignored = try seedCandidateTopic(id: "candidate-ignore", repositories: repositories)
        let useCase = CandidateTopicManagementUseCase(repositories: repositories)
        let updateDate = candidateFixedDate.addingTimeInterval(100)

        let activeTopic = try useCase.trackCandidate(id: tracked.id, updatedAt: updateDate)
        let ignoredTopic = try useCase.ignoreCandidate(id: ignored.id, updatedAt: updateDate)

        XCTAssertEqual(activeTopic.status, .active)
        XCTAssertEqual(ignoredTopic.status, .ignored)
        XCTAssertEqual(try repositories.topics.fetch(id: tracked.id)?.status, .active)
        XCTAssertEqual(try repositories.topics.fetch(id: ignored.id)?.status, .ignored)
        XCTAssertEqual(activeTopic.updatedAt, updateDate)
        XCTAssertEqual(ignoredTopic.updatedAt, updateDate)
    }

    func testCandidateRenameAndDescriptionPersist() throws {
        let repositories = try makeCandidateRepositories()
        let topic = try seedCandidateTopic(id: "candidate-edit", repositories: repositories)
        let useCase = CandidateTopicManagementUseCase(repositories: repositories)
        let updateDate = candidateFixedDate.addingTimeInterval(200)

        let renamed = try useCase.renameCandidate(
            id: topic.id,
            name: "  AI coding tools reshape Swift onboarding  ",
            updatedAt: updateDate
        )
        let described = try useCase.updateCandidateDescription(
            id: topic.id,
            description: "  Tracks onboarding changes from AI coding tools.  ",
            updatedAt: updateDate
        )
        let saved = try XCTUnwrap(repositories.topics.fetch(id: topic.id))

        XCTAssertEqual(renamed.name, "AI coding tools reshape Swift onboarding")
        XCTAssertEqual(described.description, "Tracks onboarding changes from AI coding tools.")
        XCTAssertEqual(saved.name, "AI coding tools reshape Swift onboarding")
        XCTAssertEqual(saved.description, "Tracks onboarding changes from AI coding tools.")
        XCTAssertEqual(saved.updatedAt, updateDate)
    }

    func testCandidatePreviewIncludesPreviewBriefAndRelatedArticles() throws {
        let repositories = try makeCandidateRepositories()
        let topic = try seedCandidateTopic(id: "candidate-preview", repositories: repositories)
        let article = try seedCandidateArticle(id: "article-preview", repositories: repositories)
        let relationship = TopicArticle(
            topicID: topic.id,
            articleID: article.id,
            confidence: 0.83,
            reason: "The article introduces the candidate topic.",
            contributionType: .newEvent,
            createdAt: candidateFixedDate
        )
        let brief = TopicBrief(
            topicID: topic.id,
            briefType: .preview,
            currentTakeaway: "Candidate preview takeaway.",
            modelName: "gpt-test",
            generatedAt: candidateFixedDate
        )
        try repositories.topicArticles.save(relationship)
        try repositories.topicBriefs.save(brief)
        let useCase = CandidateTopicManagementUseCase(repositories: repositories)

        let preview = try useCase.previewCandidate(id: topic.id)

        XCTAssertEqual(preview.topic.id, topic.id)
        XCTAssertEqual(preview.previewBrief?.currentTakeaway, "Candidate preview takeaway.")
        XCTAssertEqual(preview.articleCount, 1)
        XCTAssertEqual(preview.relatedArticles.map(\.id), [article.id])
    }

    func testDuplicateCandidateRenameIsRejectedByNormalizedName() throws {
        let repositories = try makeCandidateRepositories()
        let topic = try seedCandidateTopic(
            id: "candidate-original",
            name: "AI coding tools reshape Swift onboarding",
            repositories: repositories
        )
        try seedCandidateTopic(
            id: "candidate-duplicate",
            name: "AI coding tools reshape Python onboarding",
            repositories: repositories
        )
        let useCase = CandidateTopicManagementUseCase(repositories: repositories)

        XCTAssertThrowsError(
            try useCase.renameCandidate(id: topic.id, name: "  AI   coding tools reshape Python onboarding  ")
        ) { error in
            XCTAssertEqual(
                error as? CandidateTopicManagementError,
                .duplicateCandidateName("AI   coding tools reshape Python onboarding")
            )
        }
    }

    func testActionsRequireCandidateTopic() throws {
        let repositories = try makeCandidateRepositories()
        let activeTopic = Topic(
            id: "active-topic",
            name: "Active topic",
            description: "Already tracked.",
            status: .active,
            createdAt: candidateFixedDate,
            updatedAt: candidateFixedDate
        )
        try repositories.topics.save(activeTopic)
        let useCase = CandidateTopicManagementUseCase(repositories: repositories)

        XCTAssertThrowsError(try useCase.ignoreCandidate(id: activeTopic.id)) { error in
            XCTAssertEqual(error as? CandidateTopicManagementError, .topicIsNotCandidate(activeTopic.id))
        }
    }
}

private func makeCandidateRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarCandidateTopicManagementUseCaseTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

@discardableResult
private func seedCandidateTopic(
    id: String,
    name: String = "AI coding tools reshape junior developer onboarding",
    repositories: RSSRadarRepositories
) throws -> Topic {
    let topic = Topic(
        id: id,
        name: name,
        description: "Tracks onboarding impact from AI coding tools.",
        entities: ["AI coding tools", "junior developers"],
        status: .candidate,
        importanceScore: 0.72,
        createdAt: candidateFixedDate,
        updatedAt: candidateFixedDate
    )
    try repositories.topics.save(topic)
    return topic
}

@discardableResult
private func seedCandidateArticle(id: String, repositories: RSSRadarRepositories) throws -> Article {
    let feed = Feed(
        id: "feed-\(id)",
        title: "Example Feed",
        url: URL(string: "https://example.com/\(id)/feed.xml")!,
        createdAt: candidateFixedDate,
        updatedAt: candidateFixedDate
    )
    let article = Article(
        id: id,
        feedID: feed.id,
        title: "AI coding onboarding update",
        url: URL(string: "https://example.com/\(id)")!,
        content: "AI coding tools changed onboarding practices.",
        status: .assigned,
        createdAt: candidateFixedDate,
        updatedAt: candidateFixedDate
    )
    try repositories.feeds.save(feed)
    try repositories.articles.save(article)
    return article
}

private let candidateFixedDate = Date(timeIntervalSince1970: 1_700_100_000)
