import Foundation
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class ManualFeedAddUseCaseTests: XCTestCase {
    func testAddFeedPersistsParsedFeedThroughRepository() async throws {
        let repositories = try makeRepositories()
        let useCase = ManualFeedAddUseCase(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "valid-rss")
        )

        let feed = try await useCase.addFeed(urlString: "https://persisted.example.com/feed.xml", now: fixedDate)
        let persistedFeed = try XCTUnwrap(repositories.feeds.fetch(id: feed.id))

        XCTAssertEqual(persistedFeed.title, "Persisted RSSRadar Feed")
        XCTAssertEqual(persistedFeed.siteURL?.absoluteString, "https://persisted.example.com")
        XCTAssertEqual(persistedFeed.status, .active)
        XCTAssertEqual(persistedFeed.lastCheckedAt, fixedDate)
        XCTAssertEqual(persistedFeed.lastSuccessAt, fixedDate)
        XCTAssertNil(persistedFeed.errorMessage)
    }

    func testAddFeedPersistsErrorFeedThroughRepository() async throws {
        let repositories = try makeRepositories()
        let useCase = ManualFeedAddUseCase(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "invalid-rss")
        )

        let feed = try await useCase.addFeed(urlString: "https://broken.example.com/feed.xml", now: fixedDate)
        let persistedFeed = try XCTUnwrap(repositories.feeds.fetch(id: feed.id))

        XCTAssertEqual(persistedFeed.title, "broken.example.com")
        XCTAssertEqual(persistedFeed.status, .error)
        XCTAssertEqual(persistedFeed.lastCheckedAt, fixedDate)
        XCTAssertNil(persistedFeed.lastSuccessAt)
        XCTAssertNotNil(persistedFeed.errorMessage)
    }
}

private extension ManualFeedAddUseCaseTests {
    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarManualFeedAddUseCaseTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }
}

private struct FixtureFeedDataLoader: FeedDataLoader {
    var fixtureName: String

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let fixtureURL = Bundle.module.url(forResource: fixtureName, withExtension: "xml")!
        let data = try Data(contentsOf: fixtureURL)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
