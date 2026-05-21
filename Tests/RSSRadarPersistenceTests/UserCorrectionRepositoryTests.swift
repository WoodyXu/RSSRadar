import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarPersistence

final class UserCorrectionRepositoryTests: XCTestCase {
    func testUserCorrectionRepositoryCreatesReadsAndListsCorrections() throws {
        let repositories = try makeRepositories()
        let feed = makeFeed(id: "feed-1")
        let article = makeArticle(id: "article-1", feedID: feed.id)
        let topic = makeTopic(id: "topic-1")
        let correction = UserCorrection(
            id: "correction-1",
            correctionType: .addArticleToTopic,
            topicID: topic.id,
            articleID: article.id,
            oldValue: nil,
            newValue: "topic_id=topic-1;article_id=article-1",
            createdAt: fixedDate
        )

        try repositories.feeds.save(feed)
        try repositories.articles.save(article)
        try repositories.topics.save(topic)
        try repositories.userCorrections.save(correction)

        XCTAssertEqual(try repositories.userCorrections.fetch(id: correction.id), correction)
        XCTAssertEqual(try repositories.userCorrections.fetchForTopic(id: topic.id), [correction])
        XCTAssertEqual(try repositories.userCorrections.fetchForArticle(id: article.id), [correction])
        XCTAssertEqual(try repositories.userCorrections.fetchAll(), [correction])
    }
}

private extension UserCorrectionRepositoryTests {
    var fixedDate: Date {
        Date(timeIntervalSince1970: 1_778_889_600)
    }

    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarUserCorrectionRepositoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }

    func makeFeed(id: String, title: String = "Feed") -> Feed {
        Feed(
            id: id,
            title: title,
            url: URL(string: "https://example.com/\(id).xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func makeArticle(id: String, feedID: String, title: String = "Article") -> Article {
        Article(
            id: id,
            feedID: feedID,
            title: title,
            url: URL(string: "https://example.com/articles/\(id)")!,
            status: .assigned,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func makeTopic(id: String, name: String = "Topic") -> Topic {
        Topic(
            id: id,
            name: name,
            description: "Description",
            status: .active,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }
}
