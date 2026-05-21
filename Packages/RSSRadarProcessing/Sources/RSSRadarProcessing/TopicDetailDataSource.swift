import Foundation
import RSSRadarCore
import RSSRadarPersistence

public final class TopicDetailDataSource: @unchecked Sendable {
    private let repositories: RSSRadarRepositories

    public init(repositories: RSSRadarRepositories) {
        self.repositories = repositories
    }

    public func load(topicID: String, briefType requestedBriefType: TopicBriefType? = nil) throws -> TopicDetailSnapshot {
        guard let topic = try repositories.topics.fetch(id: topicID) else {
            throw TopicDetailDataSourceError.topicNotFound(topicID)
        }

        let briefType = requestedBriefType ?? defaultBriefType(for: topic)
        let brief = try repositories.topicBriefs.fetch(topicID: topic.id, briefType: briefType)
        let relationships = try repositories.topicArticles.fetchForTopic(id: topic.id)
        let relationshipByArticleID = Dictionary(uniqueKeysWithValues: relationships.map { ($0.articleID, $0) })
        let relatedArticles = try makeRelatedArticles(brief: brief, relationships: relationships)
        let evidence = try makeEvidenceItems(brief: brief, relationshipByArticleID: relationshipByArticleID)

        return TopicDetailSnapshot(
            topic: topic,
            briefType: briefType,
            brief: brief,
            currentTakeaway: brief?.currentTakeaway,
            latestChanges: brief?.latestChanges ?? [],
            timeline: brief?.timeline ?? [],
            viewpoints: brief?.viewpoints ?? [],
            evidence: evidence,
            questionsToWatch: brief?.questionsToWatch ?? [],
            relatedArticles: relatedArticles
        )
    }

    private func defaultBriefType(for topic: Topic) -> TopicBriefType {
        topic.status == .candidate ? .preview : .full
    }

    private func makeRelatedArticles(brief: TopicBrief?, relationships: [TopicArticle]) throws -> [TopicDetailArticle] {
        let articleIDs = orderedArticleIDs(brief: brief, relationships: relationships)
        let relationshipByArticleID = Dictionary(uniqueKeysWithValues: relationships.map { ($0.articleID, $0) })

        return try articleIDs.compactMap { articleID in
            guard let article = try repositories.articles.fetch(id: articleID) else {
                return nil
            }
            let feed = try repositories.feeds.fetch(id: article.feedID)
            let analysis = try repositories.articleAnalyses.fetch(articleID: article.id)
            let relationship = relationshipByArticleID[article.id]

            return TopicDetailArticle(
                article: article,
                sourceName: feed?.title,
                analysisSummary: analysis?.summary,
                contributionType: relationship?.contributionType,
                relationshipReason: relationship?.reason,
                confidence: relationship?.confidence
            )
        }
    }

    private func orderedArticleIDs(brief: TopicBrief?, relationships: [TopicArticle]) -> [String] {
        var seen: Set<String> = []
        var articleIDs: [String] = []

        for articleID in brief?.relatedArticleIDs ?? [] where seen.insert(articleID).inserted {
            articleIDs.append(articleID)
        }
        for relationship in relationships where seen.insert(relationship.articleID).inserted {
            articleIDs.append(relationship.articleID)
        }

        return articleIDs
    }

    private func makeEvidenceItems(
        brief: TopicBrief?,
        relationshipByArticleID: [String: TopicArticle]
    ) throws -> [TopicDetailEvidence] {
        try (brief?.evidence ?? []).map { evidence in
            let article = try repositories.articles.fetch(id: evidence.sourceArticleID)
            let feed = try article.flatMap { try repositories.feeds.fetch(id: $0.feedID) }
            let analysis = try repositories.articleAnalyses.fetch(articleID: evidence.sourceArticleID)
            let relationship = relationshipByArticleID[evidence.sourceArticleID]

            return TopicDetailEvidence(
                evidence: evidence,
                sourceArticle: article,
                sourceName: feed?.title ?? evidence.sourceName,
                analysisSummary: analysis?.summary,
                contributionType: relationship?.contributionType
            )
        }
    }
}

public struct TopicDetailSnapshot: Equatable, Sendable {
    public var topic: Topic
    public var briefType: TopicBriefType
    public var brief: TopicBrief?
    public var currentTakeaway: String?
    public var latestChanges: [TopicBriefChange]
    public var timeline: [TopicBriefTimelineItem]
    public var viewpoints: [TopicBriefViewpoint]
    public var evidence: [TopicDetailEvidence]
    public var questionsToWatch: [String]
    public var relatedArticles: [TopicDetailArticle]

    public init(
        topic: Topic,
        briefType: TopicBriefType,
        brief: TopicBrief?,
        currentTakeaway: String?,
        latestChanges: [TopicBriefChange],
        timeline: [TopicBriefTimelineItem],
        viewpoints: [TopicBriefViewpoint],
        evidence: [TopicDetailEvidence],
        questionsToWatch: [String],
        relatedArticles: [TopicDetailArticle]
    ) {
        self.topic = topic
        self.briefType = briefType
        self.brief = brief
        self.currentTakeaway = currentTakeaway
        self.latestChanges = latestChanges
        self.timeline = timeline
        self.viewpoints = viewpoints
        self.evidence = evidence
        self.questionsToWatch = questionsToWatch
        self.relatedArticles = relatedArticles
    }
}

public struct TopicDetailEvidence: Equatable, Sendable {
    public var evidence: TopicBriefEvidence
    public var sourceArticle: Article?
    public var sourceName: String
    public var analysisSummary: String?
    public var contributionType: TopicContributionType?

    public init(
        evidence: TopicBriefEvidence,
        sourceArticle: Article?,
        sourceName: String,
        analysisSummary: String?,
        contributionType: TopicContributionType?
    ) {
        self.evidence = evidence
        self.sourceArticle = sourceArticle
        self.sourceName = sourceName
        self.analysisSummary = analysisSummary
        self.contributionType = contributionType
    }
}

public struct TopicDetailArticle: Equatable, Sendable {
    public var article: Article
    public var sourceName: String?
    public var analysisSummary: String?
    public var contributionType: TopicContributionType?
    public var relationshipReason: String?
    public var confidence: Double?

    public init(
        article: Article,
        sourceName: String?,
        analysisSummary: String?,
        contributionType: TopicContributionType?,
        relationshipReason: String?,
        confidence: Double?
    ) {
        self.article = article
        self.sourceName = sourceName
        self.analysisSummary = analysisSummary
        self.contributionType = contributionType
        self.relationshipReason = relationshipReason
        self.confidence = confidence
    }
}

public enum TopicDetailDataSourceError: Error, Equatable, LocalizedError {
    case topicNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .topicNotFound(topicID):
            "Topic was not found: \(topicID)."
        }
    }
}
