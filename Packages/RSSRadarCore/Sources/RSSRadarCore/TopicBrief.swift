import Foundation

public enum TopicBriefType: String, Codable, CaseIterable, Sendable {
    case full
    case preview
}

public struct TopicBriefChange: Codable, Equatable, Sendable {
    public var text: String
    public var articleIDs: [String]

    public enum CodingKeys: String, CodingKey {
        case text
        case articleIDs = "article_ids"
    }

    public init(text: String, articleIDs: [String] = []) {
        self.text = text
        self.articleIDs = articleIDs
    }
}

public struct TopicBriefTimelineItem: Codable, Equatable, Sendable {
    public var date: Date?
    public var title: String
    public var description: String
    public var articleIDs: [String]

    public enum CodingKeys: String, CodingKey {
        case date
        case title
        case description
        case articleIDs = "article_ids"
    }

    public init(date: Date? = nil, title: String, description: String, articleIDs: [String] = []) {
        self.date = date
        self.title = title
        self.description = description
        self.articleIDs = articleIDs
    }
}

public struct TopicBriefViewpoint: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var articleIDs: [String]

    public enum CodingKeys: String, CodingKey {
        case title
        case summary
        case articleIDs = "article_ids"
    }

    public init(title: String, summary: String, articleIDs: [String] = []) {
        self.title = title
        self.summary = summary
        self.articleIDs = articleIDs
    }
}

public struct TopicBriefEvidence: Codable, Equatable, Sendable {
    public var content: String
    public var sourceArticleID: String
    public var sourceArticleTitle: String
    public var sourceName: String
    public var sourceURL: URL
    public var publishedAt: Date?

    public enum CodingKeys: String, CodingKey {
        case content
        case sourceArticleID = "source_article_id"
        case sourceArticleTitle = "source_article_title"
        case sourceName = "source_name"
        case sourceURL = "source_url"
        case publishedAt = "published_at"
    }

    public init(
        content: String,
        sourceArticleID: String,
        sourceArticleTitle: String,
        sourceName: String,
        sourceURL: URL,
        publishedAt: Date? = nil
    ) {
        self.content = content
        self.sourceArticleID = sourceArticleID
        self.sourceArticleTitle = sourceArticleTitle
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.publishedAt = publishedAt
    }
}

public struct TopicBrief: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var topicID: String
    public var briefType: TopicBriefType
    public var currentTakeaway: String
    public var latestChanges: [TopicBriefChange]
    public var timeline: [TopicBriefTimelineItem]
    public var viewpoints: [TopicBriefViewpoint]
    public var evidence: [TopicBriefEvidence]
    public var questionsToWatch: [String]
    public var relatedArticleIDs: [String]
    public var modelName: String
    public var generatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case topicID = "topic_id"
        case briefType = "brief_type"
        case currentTakeaway = "current_takeaway"
        case latestChanges = "latest_changes"
        case timeline
        case viewpoints
        case evidence
        case questionsToWatch = "questions_to_watch"
        case relatedArticleIDs = "related_article_ids"
        case modelName = "model_name"
        case generatedAt = "generated_at"
    }

    public init(
        id: String = DomainID.make(),
        topicID: String,
        briefType: TopicBriefType,
        currentTakeaway: String,
        latestChanges: [TopicBriefChange] = [],
        timeline: [TopicBriefTimelineItem] = [],
        viewpoints: [TopicBriefViewpoint] = [],
        evidence: [TopicBriefEvidence] = [],
        questionsToWatch: [String] = [],
        relatedArticleIDs: [String] = [],
        modelName: String,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.topicID = topicID
        self.briefType = briefType
        self.currentTakeaway = currentTakeaway
        self.latestChanges = latestChanges
        self.timeline = timeline
        self.viewpoints = viewpoints
        self.evidence = evidence
        self.questionsToWatch = questionsToWatch
        self.relatedArticleIDs = relatedArticleIDs
        self.modelName = modelName
        self.generatedAt = generatedAt
    }
}
