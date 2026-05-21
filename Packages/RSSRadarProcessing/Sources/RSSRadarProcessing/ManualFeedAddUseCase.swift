import Foundation
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence

public final class ManualFeedAddUseCase {
    private let service: ManualFeedAddService

    public init(repositories: RSSRadarRepositories, loader: FeedDataLoader = URLSession.shared) {
        service = ManualFeedAddService(
            loader: loader,
            store: FeedRepositoryStore(repository: repositories.feeds)
        )
    }

    @discardableResult
    public func addFeed(urlString: String, now: Date = Date()) async throws -> Feed {
        try await service.addFeed(urlString: urlString, now: now)
    }
}

final class FeedRepositoryStore: FeedStore, OPMLFeedStore {
    private let repository: FeedRepository

    init(repository: FeedRepository) {
        self.repository = repository
    }

    func fetchAll() throws -> [Feed] {
        try repository.fetchAll()
    }

    func save(_ feed: Feed) throws {
        try repository.save(feed)
    }
}
