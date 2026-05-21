import Foundation
import RSSRadarCore
import RSSRadarPersistence

public final class TodayPageDataSource: @unchecked Sendable {
    private let repositories: RSSRadarRepositories
    private let calendar: Calendar

    public init(repositories: RSSRadarRepositories, calendar: Calendar = .current) {
        self.repositories = repositories
        self.calendar = calendar
    }

    public func load(now: Date = Date()) throws -> TodayPageSnapshot {
        let startOfDay = calendar.startOfDay(for: now)
        let topics = try repositories.topics.fetchAll()
        let activeTopics = topics.filter { $0.status == .active }
        let candidateTopics = topics.filter { $0.status == .candidate }

        let activeItems = try activeTopics.compactMap { topic in
            try makeTopicItem(topic: topic, briefType: .full, since: startOfDay, now: now)
        }
        let candidateItems = try candidateTopics.compactMap { topic in
            try makeTopicItem(topic: topic, briefType: .preview, since: startOfDay, now: now)
        }

        return TodayPageSnapshot(
            scanStatus: try makeScanStatus(since: startOfDay),
            importantTopics: sort(activeItems),
            newCandidateTopics: sort(candidateItems),
            trackedTopicUpdates: sort(activeItems.filter { !$0.latestChanges.isEmpty || $0.newArticleCount > 0 })
        )
    }

    private func makeTopicItem(
        topic: Topic,
        briefType: TopicBriefType,
        since: Date,
        now: Date
    ) throws -> TodayTopicItem? {
        let relationships = try repositories.topicArticles.fetchForTopic(id: topic.id)
        let relatedArticles = try relationships.compactMap { try repositories.articles.fetch(id: $0.articleID) }
        let newArticleCount = relationships.filter { $0.createdAt >= since }.count
        let brief = try repositories.topicBriefs.fetch(topicID: topic.id, briefType: briefType)
        let latestActivityAt = latestActivityDate(
            topic: topic,
            brief: brief,
            relationships: relationships,
            articles: relatedArticles
        )

        guard latestActivityAt >= since else {
            return nil
        }

        let recentChanges = brief?.latestChanges.map(\.text) ?? []
        let primarySources = try primarySources(for: relatedArticles)
        let score = rankingScore(
            topic: topic,
            status: topic.status,
            latestActivityAt: latestActivityAt,
            newArticleCount: newArticleCount,
            now: now
        )

        return TodayTopicItem(
            topic: topic,
            brief: brief,
            currentTakeaway: brief?.currentTakeaway,
            latestChanges: recentChanges,
            newArticleCount: newArticleCount,
            relatedArticleCount: relationships.count,
            primarySources: primarySources,
            latestActivityAt: latestActivityAt,
            score: score
        )
    }

    private func latestActivityDate(
        topic: Topic,
        brief: TopicBrief?,
        relationships: [TopicArticle],
        articles: [Article]
    ) -> Date {
        let relationshipDates = relationships.map(\.createdAt)
        let articleDates = articles.map(\.updatedAt)
        let briefDate = brief.map(\.generatedAt)
        let dates = [topic.updatedAt] + relationshipDates + articleDates + [briefDate].compactMap { $0 }
        return dates.max() ?? topic.updatedAt
    }

    private func primarySources(for articles: [Article]) throws -> [String] {
        var seen: Set<String> = []
        var sources: [String] = []

        for article in articles {
            guard let feed = try repositories.feeds.fetch(id: article.feedID) else {
                continue
            }
            if seen.insert(feed.title).inserted {
                sources.append(feed.title)
            }
        }

        return sources
    }

    private func makeScanStatus(since: Date) throws -> TodayScanStatus {
        let feeds = try repositories.feeds.fetchAll()
        let jobs = try repositories.processingJobs.fetchAll()
        let articles = try repositories.articles.fetchAll()
        let logs = try repositories.operationLogs.fetchRecent(limit: 1)

        let feedScanDates = feeds.compactMap(\.lastCheckedAt)
        let jobFinishDates = jobs.compactMap(\.finishedAt)
        let lastScanAt = (feedScanDates + jobFinishDates).max()
        let processedArticleCount = articles.filter { article in
            article.updatedAt >= since && [.parsed, .analyzed, .assigned].contains(article.status)
        }.count
        let failedJobCount = jobs.filter { $0.status == .failed }.count
        let failedArticleCount = articles.filter { $0.status == .failed }.count
        let pendingJobCount = jobs.filter { $0.status == .pending || $0.status == .running }.count

        return TodayScanStatus(
            lastScanAt: lastScanAt,
            processedArticleCount: processedArticleCount,
            failedCount: failedJobCount + failedArticleCount,
            pendingJobCount: pendingJobCount,
            latestLog: logs.first
        )
    }

    private func rankingScore(
        topic: Topic,
        status: TopicStatus,
        latestActivityAt: Date,
        newArticleCount: Int,
        now: Date
    ) -> Double {
        let recencyScore = max(0, 1 - now.timeIntervalSince(latestActivityAt) / (24 * 60 * 60))
        let importanceScore = min(max(topic.importanceScore ?? 0, 0), 1)
        let newArticleCountScore = min(Double(newArticleCount) / 5, 1)
        let activeTopicBonus = status == .active ? 1.0 : 0.0

        return recencyScore * 0.35
            + importanceScore * 0.30
            + newArticleCountScore * 0.20
            + activeTopicBonus * 0.15
    }

    private func sort(_ items: [TodayTopicItem]) -> [TodayTopicItem] {
        items.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.latestActivityAt != rhs.latestActivityAt {
                return lhs.latestActivityAt > rhs.latestActivityAt
            }
            if lhs.topic.name != rhs.topic.name {
                return lhs.topic.name.localizedStandardCompare(rhs.topic.name) == .orderedAscending
            }
            return lhs.topic.id < rhs.topic.id
        }
    }
}

public struct TodayPageSnapshot: Equatable, Sendable {
    public var scanStatus: TodayScanStatus
    public var importantTopics: [TodayTopicItem]
    public var newCandidateTopics: [TodayTopicItem]
    public var trackedTopicUpdates: [TodayTopicItem]

    public init(
        scanStatus: TodayScanStatus,
        importantTopics: [TodayTopicItem],
        newCandidateTopics: [TodayTopicItem],
        trackedTopicUpdates: [TodayTopicItem]
    ) {
        self.scanStatus = scanStatus
        self.importantTopics = importantTopics
        self.newCandidateTopics = newCandidateTopics
        self.trackedTopicUpdates = trackedTopicUpdates
    }
}

public struct TodayScanStatus: Equatable, Sendable {
    public var lastScanAt: Date?
    public var processedArticleCount: Int
    public var failedCount: Int
    public var pendingJobCount: Int
    public var latestLog: OperationLog?

    public init(
        lastScanAt: Date?,
        processedArticleCount: Int,
        failedCount: Int,
        pendingJobCount: Int,
        latestLog: OperationLog?
    ) {
        self.lastScanAt = lastScanAt
        self.processedArticleCount = processedArticleCount
        self.failedCount = failedCount
        self.pendingJobCount = pendingJobCount
        self.latestLog = latestLog
    }
}

public struct TodayTopicItem: Equatable, Sendable {
    public var topic: Topic
    public var brief: TopicBrief?
    public var currentTakeaway: String?
    public var latestChanges: [String]
    public var newArticleCount: Int
    public var relatedArticleCount: Int
    public var primarySources: [String]
    public var latestActivityAt: Date
    public var score: Double

    public init(
        topic: Topic,
        brief: TopicBrief?,
        currentTakeaway: String?,
        latestChanges: [String],
        newArticleCount: Int,
        relatedArticleCount: Int,
        primarySources: [String],
        latestActivityAt: Date,
        score: Double
    ) {
        self.topic = topic
        self.brief = brief
        self.currentTakeaway = currentTakeaway
        self.latestChanges = latestChanges
        self.newArticleCount = newArticleCount
        self.relatedArticleCount = relatedArticleCount
        self.primarySources = primarySources
        self.latestActivityAt = latestActivityAt
        self.score = score
    }
}
