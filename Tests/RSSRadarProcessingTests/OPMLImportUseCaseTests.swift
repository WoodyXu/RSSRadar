import Foundation
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class OPMLImportUseCaseTests: XCTestCase {
    func testImportOPMLPersistsFeedsAndSkipsDuplicatesThroughRepository() throws {
        let repositories = try makeRepositories()
        try repositories.feeds.save(Feed(
            title: "Existing Feed",
            url: URL(string: "https://example.com/ai.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        ))
        let useCase = OPMLImportUseCase(repositories: repositories)

        let result = try useCase.importOPML(data: fixtureData("feeds"), now: fixedDate)
        let persistedFeeds = try repositories.feeds.fetchAll()

        XCTAssertEqual(result.importedFeeds.count, 2)
        XCTAssertEqual(result.skippedDuplicates.count, 2)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertTrue(persistedFeeds.contains { $0.url.absoluteString == "https://example.com/ai.xml" })
        XCTAssertTrue(persistedFeeds.contains { $0.url.absoluteString == "https://fallback.example.com/rss.xml" })
        XCTAssertTrue(persistedFeeds.contains { $0.url.absoluteString == "https://untitled.example.com/feed.xml" })
        XCTAssertFalse(persistedFeeds.contains { $0.url.absoluteString == "notaurl" })
    }
}

private extension OPMLImportUseCaseTests {
    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarOPMLImportUseCaseTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let fixtureURL = Bundle.module.url(forResource: name, withExtension: "opml")!
    return try Data(contentsOf: fixtureURL)
}

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
