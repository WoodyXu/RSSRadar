import Foundation
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class UserCorrectionUseCaseTests: XCTestCase {
    func testRemoveArticleFromTopicDeletesRelationshipAndRecordsCorrection() throws {
        let repositories = try makeUserCorrectionRepositories()
        let topic = try seedCorrectionTopic(id: "topic-remove", repositories: repositories)
        let article = try seedCorrectionArticle(id: "article-remove", repositories: repositories)
        try repositories.topicArticles.save(
            TopicArticle(
                topicID: topic.id,
                articleID: article.id,
                confidence: 0.62,
                reason: "AI matched article to topic.",
                contributionType: .newOpinion,
                createdAt: userCorrectionFixedDate
            )
        )
        let useCase = UserCorrectionUseCase(repositories: repositories)

        let result = try useCase.removeArticleFromTopic(
            topicID: topic.id,
            articleID: article.id,
            correctedAt: userCorrectionFixedDate
        )

        XCTAssertNil(try repositories.topicArticles.fetch(topicID: topic.id, articleID: article.id))
        let correction = try XCTUnwrap(try repositories.userCorrections.fetch(id: result.correction.id))
        XCTAssertEqual(correction.correctionType, .removeArticleFromTopic)
        XCTAssertEqual(correction.topicID, topic.id)
        XCTAssertEqual(correction.articleID, article.id)
        XCTAssertTrue(correction.oldValue?.contains("confidence=0.62") == true)
        XCTAssertNil(correction.newValue)
        XCTAssertTrue(result.shouldPromptTopicBriefRegeneration)
        XCTAssertEqual(result.promptMessage, UserCorrectionResult.topicBriefRegenerationPrompt)
    }

    func testAddArticleToExistingTopicCreatesRelationshipAndRecordsCorrection() throws {
        let repositories = try makeUserCorrectionRepositories()
        let topic = try seedCorrectionTopic(id: "topic-add", repositories: repositories)
        let article = try seedCorrectionArticle(id: "article-add", repositories: repositories)
        let useCase = UserCorrectionUseCase(repositories: repositories)

        let result = try useCase.addArticleToExistingTopic(
            topicID: topic.id,
            articleID: article.id,
            contributionType: .newData,
            reason: "User says this adds new data.",
            correctedAt: userCorrectionFixedDate
        )

        let relationship = try XCTUnwrap(try repositories.topicArticles.fetch(topicID: topic.id, articleID: article.id))
        XCTAssertEqual(relationship.confidence, 1)
        XCTAssertEqual(relationship.reason, "User says this adds new data.")
        XCTAssertEqual(relationship.contributionType, .newData)
        let correction = try XCTUnwrap(try repositories.userCorrections.fetch(id: result.correction.id))
        XCTAssertEqual(correction.correctionType, .addArticleToTopic)
        XCTAssertEqual(correction.topicID, topic.id)
        XCTAssertEqual(correction.articleID, article.id)
        XCTAssertTrue(correction.newValue?.contains("contribution_type=new_data") == true)
        XCTAssertEqual(result.topicArticle, relationship)
        XCTAssertTrue(result.shouldPromptTopicBriefRegeneration)
    }

    func testCreateTopicFromArticleCreatesActiveTopicRelationshipAndCorrection() throws {
        let repositories = try makeUserCorrectionRepositories()
        let article = try seedCorrectionArticle(id: "article-create", repositories: repositories)
        let useCase = UserCorrectionUseCase(repositories: repositories)

        let result = try useCase.createTopicFromArticle(
            articleID: article.id,
            name: "  Claude Code adoption in enterprise Swift teams  ",
            description: "  Tracks adoption blockers and evidence.  ",
            entities: [" Claude Code ", "", "Swift"],
            contributionType: .newEvent,
            reason: "User created this from a seed article.",
            correctedAt: userCorrectionFixedDate
        )

        let topic = try XCTUnwrap(result.topic)
        let savedTopic = try XCTUnwrap(try repositories.topics.fetch(id: topic.id))
        XCTAssertEqual(savedTopic.status, .active)
        XCTAssertEqual(savedTopic.name, "Claude Code adoption in enterprise Swift teams")
        XCTAssertEqual(savedTopic.description, "Tracks adoption blockers and evidence.")
        XCTAssertEqual(savedTopic.entities, ["Claude Code", "Swift"])
        XCTAssertNil(savedTopic.originalAIName)
        let relationship = try XCTUnwrap(try repositories.topicArticles.fetch(topicID: topic.id, articleID: article.id))
        XCTAssertEqual(relationship.confidence, 1)
        XCTAssertEqual(relationship.reason, "User created this from a seed article.")
        let correction = try XCTUnwrap(try repositories.userCorrections.fetch(id: result.correction.id))
        XCTAssertEqual(correction.correctionType, .createTopicFromArticle)
        XCTAssertEqual(correction.topicID, topic.id)
        XCTAssertEqual(correction.articleID, article.id)
        XCTAssertTrue(correction.newValue?.contains("topic_name=Claude Code adoption") == true)
        XCTAssertTrue(result.shouldPromptTopicBriefRegeneration)
    }

    func testCorrectionsValidateExistingObjectsAndInputs() throws {
        let repositories = try makeUserCorrectionRepositories()
        let article = try seedCorrectionArticle(id: "article-errors", repositories: repositories)
        let topic = try seedCorrectionTopic(id: "topic-errors", repositories: repositories)
        let useCase = UserCorrectionUseCase(repositories: repositories)

        XCTAssertThrowsError(try useCase.removeArticleFromTopic(topicID: topic.id, articleID: article.id)) { error in
            XCTAssertEqual(
                error as? UserCorrectionError,
                .topicArticleNotFound(topicID: topic.id, articleID: article.id)
            )
        }
        XCTAssertThrowsError(
            try useCase.addArticleToExistingTopic(topicID: topic.id, articleID: article.id, reason: " ")
        ) { error in
            XCTAssertEqual(error as? UserCorrectionError, .emptyReason)
        }
        XCTAssertThrowsError(
            try useCase.createTopicFromArticle(articleID: article.id, name: " ", description: "Description")
        ) { error in
            XCTAssertEqual(error as? UserCorrectionError, .emptyTopicName)
        }
    }
}

private func makeUserCorrectionRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarUserCorrectionUseCaseTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

@discardableResult
private func seedCorrectionTopic(id: String, repositories: RSSRadarRepositories) throws -> Topic {
    let topic = Topic(
        id: id,
        name: "AI coding tools reshape junior developer onboarding",
        description: "Tracks onboarding impact from AI coding tools.",
        entities: ["AI coding tools", "junior developers"],
        status: .active,
        importanceScore: 0.72,
        createdAt: userCorrectionFixedDate,
        updatedAt: userCorrectionFixedDate
    )
    try repositories.topics.save(topic)
    return topic
}

@discardableResult
private func seedCorrectionArticle(id: String, repositories: RSSRadarRepositories) throws -> Article {
    let feed = Feed(
        id: "feed-\(id)",
        title: "Example Feed",
        url: URL(string: "https://example.com/\(id)/feed.xml")!,
        createdAt: userCorrectionFixedDate,
        updatedAt: userCorrectionFixedDate
    )
    let article = Article(
        id: id,
        feedID: feed.id,
        title: "AI coding onboarding update",
        url: URL(string: "https://example.com/\(id)")!,
        content: "AI coding tools changed onboarding practices.",
        status: .assigned,
        importanceScore: 0.81,
        createdAt: userCorrectionFixedDate,
        updatedAt: userCorrectionFixedDate
    )
    try repositories.feeds.save(feed)
    try repositories.articles.save(article)
    return article
}

private let userCorrectionFixedDate = Date(timeIntervalSince1970: 1_700_200_000)
