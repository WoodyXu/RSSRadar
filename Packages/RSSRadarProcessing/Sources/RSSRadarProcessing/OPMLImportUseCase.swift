import Foundation
import RSSRadarFeeds
import RSSRadarPersistence

public final class OPMLImportUseCase {
    private let service: OPMLImportService

    public init(repositories: RSSRadarRepositories) {
        service = OPMLImportService(store: FeedRepositoryStore(repository: repositories.feeds))
    }

    @discardableResult
    public func importOPML(data: Data, now: Date = Date()) throws -> OPMLImportResult {
        try service.importOPML(data: data, now: now)
    }
}
