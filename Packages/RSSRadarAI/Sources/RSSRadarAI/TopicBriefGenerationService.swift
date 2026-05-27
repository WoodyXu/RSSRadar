import Foundation
import RSSRadarCore

public protocol TopicBriefGenerating: Sendable {
    func generateBrief(
        topic: Topic,
        relatedArticles: [TopicBriefSourceArticle],
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date
    ) async throws -> TopicBrief
}

public struct TopicBriefSourceArticle: Equatable, Sendable {
    public var article: Article
    public var analysis: ArticleAnalysis
    public var feedTitle: String
    public var contributionType: TopicContributionType

    public init(
        article: Article,
        analysis: ArticleAnalysis,
        feedTitle: String,
        contributionType: TopicContributionType
    ) {
        self.article = article
        self.analysis = analysis
        self.feedTitle = feedTitle
        self.contributionType = contributionType
    }
}

public final class TopicBriefGenerationService: TopicBriefGenerating, @unchecked Sendable {
    private let provider: any AIProvider
    private let promptStore: PromptTemplateStore
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let dateFormatter: ISO8601DateFormatter

    public init(
        provider: any AIProvider,
        promptStore: PromptTemplateStore = PromptTemplateStore()
    ) {
        self.provider = provider
        self.promptStore = promptStore
        jsonDecoder = JSONDecoder()
        jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func generateBrief(
        topic: Topic,
        relatedArticles: [TopicBriefSourceArticle],
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date = Date()
    ) async throws -> TopicBrief {
        let kind: PromptTemplateKind = briefType == .full ? .topicBrief : .candidateTopicPreview
        let prompt = try promptStore.load(kind).render(
            variables: [
                "topic_json": topicPromptJSON(topic),
                "related_articles_json": relatedArticlesPromptJSON(relatedArticles)
            ]
        )
        let response = try await provider.complete(
            AIProviderRequest(
                model: modelName,
                messages: [AIMessage(role: .user, content: prompt)],
                temperature: 0.2,
                maxTokens: briefType == .full ? 8192 : 4096,
                responseFormat: .jsonObject
            )
        )
        let output = try decodeOutput(from: response.text, validArticleIDs: Set(relatedArticles.map(\.article.id)))
        let sourceByArticleID = Dictionary(uniqueKeysWithValues: relatedArticles.map { ($0.article.id, $0) })
        let model = response.model?.trimmingCharacters(in: .whitespacesAndNewlines)

        return output.topicBrief(
            topicID: topic.id,
            briefType: briefType,
            sourceByArticleID: sourceByArticleID,
            modelName: model?.isEmpty == false ? model! : modelName,
            generatedAt: generatedAt
        )
    }

    private func topicPromptJSON(_ topic: Topic) -> String {
        encodedJSONString(TopicBriefTopicPayload(topic: topic))
    }

    private func relatedArticlesPromptJSON(_ relatedArticles: [TopicBriefSourceArticle]) -> String {
        encodedJSONString(relatedArticles.map(TopicBriefArticlePayload.init(source:)))
    }

    private func encodedJSONString<T: Encodable>(_ value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func decodeOutput(from text: String, validArticleIDs: Set<String>) throws -> TopicBriefOutput {
        guard let data = text.data(using: .utf8) else {
            throw TopicBriefValidationError.invalidUTF8
        }

        do {
            let output = try jsonDecoder.decode(TopicBriefOutput.self, from: data)
            try output.validate(validArticleIDs: validArticleIDs)
            return output.normalized()
        } catch let error as TopicBriefValidationError {
            throw error
        } catch {
            throw TopicBriefValidationError.invalidJSON(String(describing: error))
        }
    }
}

public enum TopicBriefValidationError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case invalidJSON(String)
    case emptyField(String)
    case unknownArticleID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "AI TopicBrief output is not valid UTF-8."
        case let .invalidJSON(message):
            "AI TopicBrief output is not valid JSON: \(message)"
        case let .emptyField(name):
            "AI TopicBrief output has an empty required field: \(name)."
        case let .unknownArticleID(articleID):
            "AI TopicBrief output references an unknown article: \(articleID)."
        }
    }
}

private struct TopicBriefOutput: Decodable {
    var currentTakeaway: String
    var latestChanges: [String]
    var timeline: [TimelineItem]?
    var viewpoints: [String]?
    var evidence: [EvidenceItem]
    var questionsToWatch: [String]
    var relatedArticleIDs: [String]

    enum CodingKeys: String, CodingKey {
        case currentTakeaway = "current_takeaway"
        case latestChanges = "latest_changes"
        case timeline
        case viewpoints
        case evidence
        case questionsToWatch = "questions_to_watch"
        case relatedArticleIDs = "related_article_ids"
    }

    func validate(validArticleIDs: Set<String>) throws {
        if currentTakeaway.trimmed().isEmpty {
            throw TopicBriefValidationError.emptyField("current_takeaway")
        }
        for evidenceItem in evidence {
            try evidenceItem.validate(validArticleIDs: validArticleIDs)
        }
        for articleID in relatedArticleIDs.map({ $0.trimmed() }) where !validArticleIDs.contains(articleID) {
            throw TopicBriefValidationError.unknownArticleID(articleID)
        }
    }

    func normalized() -> Self {
        Self(
            currentTakeaway: currentTakeaway.trimmed(),
            latestChanges: latestChanges.trimmedNonEmptyValues(),
            timeline: timeline?.map { $0.normalized() }.filter { !$0.title.isEmpty || !$0.description.isEmpty },
            viewpoints: viewpoints?.trimmedNonEmptyValues(),
            evidence: evidence.map { $0.normalized() }.filter { !$0.text.isEmpty },
            questionsToWatch: questionsToWatch.trimmedNonEmptyValues(),
            relatedArticleIDs: relatedArticleIDs.trimmedNonEmptyValues()
        )
    }

    func topicBrief(
        topicID: String,
        briefType: TopicBriefType,
        sourceByArticleID: [String: TopicBriefSourceArticle],
        modelName: String,
        generatedAt: Date
    ) -> TopicBrief {
        TopicBrief(
            topicID: topicID,
            briefType: briefType,
            currentTakeaway: currentTakeaway,
            latestChanges: latestChanges.map { TopicBriefChange(text: $0) },
            timeline: (timeline ?? []).map { $0.topicTimelineItem() },
            viewpoints: (viewpoints ?? []).map { TopicBriefViewpoint(title: "观点分歧", summary: $0) },
            evidence: evidence.compactMap { $0.topicEvidence(sourceByArticleID: sourceByArticleID) },
            questionsToWatch: questionsToWatch,
            relatedArticleIDs: relatedArticleIDs,
            modelName: modelName,
            generatedAt: generatedAt
        )
    }
}

private struct TimelineItem: Decodable {
    var date: String?
    var title: String
    var description: String

    func normalized() -> Self {
        Self(date: date?.trimmedNonEmpty(), title: title.trimmed(), description: description.trimmed())
    }

    func topicTimelineItem() -> TopicBriefTimelineItem {
        TopicBriefTimelineItem(date: parsedDate, title: title, description: description)
    }

    private var parsedDate: Date? {
        guard let date, date.lowercased() != "unknown" else {
            return nil
        }
        return DateOnlyParser.date(from: date)
    }
}

private struct EvidenceItem: Decodable {
    var text: String
    var articleID: String

    enum CodingKeys: String, CodingKey {
        case text
        case articleID = "article_id"
    }

    func validate(validArticleIDs: Set<String>) throws {
        if text.trimmed().isEmpty {
            throw TopicBriefValidationError.emptyField("evidence.text")
        }
        let trimmedArticleID = articleID.trimmed()
        guard !trimmedArticleID.isEmpty else {
            throw TopicBriefValidationError.emptyField("evidence.article_id")
        }
        guard validArticleIDs.contains(trimmedArticleID) else {
            throw TopicBriefValidationError.unknownArticleID(trimmedArticleID)
        }
    }

    func normalized() -> Self {
        Self(text: text.trimmed(), articleID: articleID.trimmed())
    }

    func topicEvidence(sourceByArticleID: [String: TopicBriefSourceArticle]) -> TopicBriefEvidence? {
        guard let source = sourceByArticleID[articleID] else {
            return nil
        }
        return TopicBriefEvidence(
            content: text,
            sourceArticleID: source.article.id,
            sourceArticleTitle: source.article.title,
            sourceName: source.feedTitle,
            sourceURL: source.article.url,
            publishedAt: source.article.publishedAt
        )
    }
}

private struct TopicBriefTopicPayload: Encodable {
    var topicID: String
    var name: String
    var description: String
    var entities: [String]
    var status: String

    enum CodingKeys: String, CodingKey {
        case topicID = "topic_id"
        case name
        case description
        case entities
        case status
    }

    init(topic: Topic) {
        topicID = topic.id
        name = topic.name
        description = topic.description
        entities = topic.entities
        status = topic.status.rawValue
    }
}

private struct TopicBriefArticlePayload: Encodable {
    var articleID: String
    var title: String
    var url: String
    var source: String
    var publishedAt: String?
    var summary: String
    var keyPoints: [String]
    var entities: [String]
    var claims: [String]
    var events: [String]
    var metrics: [String]
    var contributionType: String

    enum CodingKeys: String, CodingKey {
        case articleID = "article_id"
        case title
        case url
        case source
        case publishedAt = "published_at"
        case summary
        case keyPoints = "key_points"
        case entities
        case claims
        case events
        case metrics
        case contributionType = "contribution_type"
    }

    init(source: TopicBriefSourceArticle) {
        articleID = source.article.id
        title = source.article.title
        url = source.article.url.absoluteString
        self.source = source.feedTitle
        publishedAt = source.article.publishedAt.map(DateOnlyParser.string(from:))
        summary = source.analysis.summary
        keyPoints = source.analysis.keyPoints
        entities = source.analysis.entities
        claims = source.analysis.claims
        events = source.analysis.events
        metrics = source.analysis.metrics
        contributionType = source.contributionType.rawValue
    }
}

private enum DateOnlyParser {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimmedNonEmpty() -> String? {
        let value = trimmed()
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element == String {
    func trimmedNonEmptyValues() -> [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
