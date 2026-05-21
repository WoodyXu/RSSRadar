import GRDB

enum DatabaseAccess {
    case queue(DatabaseQueue)
    case database(Database)

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        switch self {
        case let .queue(queue):
            try queue.read(block)
        case let .database(database):
            try block(database)
        }
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        switch self {
        case let .queue(queue):
            try queue.write(block)
        case let .database(database):
            try block(database)
        }
    }
}

public final class RSSRadarRepositories {
    public let feeds: FeedRepository
    public let articles: ArticleRepository
    public let articleAnalyses: ArticleAnalysisRepository
    public let topics: TopicRepository
    public let topicArticles: TopicArticleRepository
    public let topicBriefs: TopicBriefRepository
    public let appSettings: AppSettingsRepository
    public let processingJobs: ProcessingJobRepository
    public let operationLogs: OperationLogRepository

    private let database: RSSRadarDatabase

    public init(database: RSSRadarDatabase) {
        self.database = database
        let access = DatabaseAccess.queue(database.queue)
        feeds = FeedRepository(access: access)
        articles = ArticleRepository(access: access)
        articleAnalyses = ArticleAnalysisRepository(access: access)
        topics = TopicRepository(access: access)
        topicArticles = TopicArticleRepository(access: access)
        topicBriefs = TopicBriefRepository(access: access)
        appSettings = AppSettingsRepository(access: access)
        processingJobs = ProcessingJobRepository(access: access)
        operationLogs = OperationLogRepository(access: access)
    }

    public func performTransaction(_ body: (RSSRadarRepositoryTransaction) throws -> Void) throws {
        try database.queue.write { db in
            try body(RSSRadarRepositoryTransaction(database: db))
        }
    }
}

public final class RSSRadarRepositoryTransaction {
    public let feeds: FeedRepository
    public let articles: ArticleRepository
    public let articleAnalyses: ArticleAnalysisRepository
    public let topics: TopicRepository
    public let topicArticles: TopicArticleRepository
    public let topicBriefs: TopicBriefRepository
    public let appSettings: AppSettingsRepository
    public let processingJobs: ProcessingJobRepository
    public let operationLogs: OperationLogRepository

    init(database: Database) {
        let access = DatabaseAccess.database(database)
        feeds = FeedRepository(access: access)
        articles = ArticleRepository(access: access)
        articleAnalyses = ArticleAnalysisRepository(access: access)
        topics = TopicRepository(access: access)
        topicArticles = TopicArticleRepository(access: access)
        topicBriefs = TopicBriefRepository(access: access)
        appSettings = AppSettingsRepository(access: access)
        processingJobs = ProcessingJobRepository(access: access)
        operationLogs = OperationLogRepository(access: access)
    }
}
