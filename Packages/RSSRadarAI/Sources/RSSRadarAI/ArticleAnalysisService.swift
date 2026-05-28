import Foundation
import RSSRadarCore

public protocol ArticleAnalyzing: Sendable {
    func analyze(
        article: Article,
        sourceTitle: String,
        modelName: String,
        generatedAt: Date
    ) async throws -> ArticleAnalysis
}

public final class ArticleAnalysisService: ArticleAnalyzing, @unchecked Sendable {
    private static let maxPromptContentCharacters = 100_000

    private let provider: any AIProvider
    private let promptStore: PromptTemplateStore
    private let jsonDecoder: JSONDecoder
    private let dateFormatter: ISO8601DateFormatter

    public init(
        provider: any AIProvider,
        promptStore: PromptTemplateStore = PromptTemplateStore()
    ) {
        self.provider = provider
        self.promptStore = promptStore
        jsonDecoder = JSONDecoder()
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func analyze(
        article: Article,
        sourceTitle: String,
        modelName: String,
        generatedAt: Date = Date()
    ) async throws -> ArticleAnalysis {
        let prompt = try promptStore.load(.articleAnalysis).render(
            variables: promptVariables(article: article, sourceTitle: sourceTitle)
        )
        let response = try await provider.complete(
            AIProviderRequest(
                model: modelName,
                messages: [AIMessage(role: .user, content: prompt)],
                temperature: 0.2,
                maxTokens: 8192,
                responseFormat: .jsonObject
            )
        )
        let output = try decodeOutput(from: response.text)
        let model = response.model?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ArticleAnalysis(
            articleID: article.id,
            summary: output.summary,
            keyPoints: output.keyPoints,
            entities: output.entities,
            claims: output.claims,
            events: output.events,
            metrics: output.metrics,
            contentType: output.contentType,
            possibleTopics: output.possibleTopics,
            importanceScore: output.importanceScore,
            modelName: model?.isEmpty == false ? model! : modelName,
            generatedAt: generatedAt
        )
    }

    private func promptVariables(article: Article, sourceTitle: String) -> [String: String] {
        [
            "title": article.title,
            "source": sourceTitle,
            "published_at": article.publishedAt.map(dateFormatter.string(from:)) ?? "",
            "url": article.url.absoluteString,
            "rss_summary": article.rssSummary ?? "",
            "content": budgetedContent(article.content ?? "")
        ]
    }

    private func budgetedContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Self.maxPromptContentCharacters else {
            return trimmed
        }

        let prefix = trimmed.prefix(Self.maxPromptContentCharacters)
        return """
        \(prefix)

        [Content truncated by RSSRadar at \(Self.maxPromptContentCharacters) characters to keep the AI request within \
        budget.]
        """
    }

    private func decodeOutput(from text: String) throws -> ArticleAnalysisOutput {
        guard let data = text.data(using: .utf8) else {
            throw ArticleAnalysisValidationError.invalidUTF8
        }

        do {
            let output = try jsonDecoder.decode(ArticleAnalysisOutput.self, from: data)
            try output.validate()
            return output.normalized()
        } catch let error as ArticleAnalysisValidationError {
            throw error
        } catch {
            throw ArticleAnalysisValidationError.invalidJSON(String(describing: error))
        }
    }
}

public enum ArticleAnalysisValidationError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case invalidJSON(String)
    case emptyField(String)
    case importanceScoreOutOfRange(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "AI article analysis output is not valid UTF-8."
        case let .invalidJSON(message):
            "AI article analysis output is not valid JSON: \(message)"
        case let .emptyField(name):
            "AI article analysis output has an empty required field: \(name)."
        case let .importanceScoreOutOfRange(score):
            "AI article analysis importance score is outside 0...1: \(score)."
        }
    }
}

private struct ArticleAnalysisOutput: Decodable {
    var summary: String
    var keyPoints: [String]
    var entities: [String]
    var claims: [String]
    var events: [String]
    var metrics: [String]
    var contentType: ArticleContentType
    var possibleTopics: [String]
    var importanceScore: Double

    enum CodingKeys: String, CodingKey {
        case summary
        case keyPoints = "key_points"
        case entities
        case claims
        case events
        case metrics
        case contentType = "content_type"
        case possibleTopics = "possible_topics"
        case importanceScore = "importance_score"
    }

    func validate() throws {
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ArticleAnalysisValidationError.emptyField("summary")
        }
        if importanceScore < 0 || importanceScore > 1 {
            throw ArticleAnalysisValidationError.importanceScoreOutOfRange(importanceScore)
        }
    }

    func normalized() -> Self {
        Self(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            keyPoints: keyPoints.trimmedNonEmptyValues(),
            entities: entities.trimmedNonEmptyValues(),
            claims: claims.trimmedNonEmptyValues(),
            events: events.trimmedNonEmptyValues(),
            metrics: metrics.trimmedNonEmptyValues(),
            contentType: contentType,
            possibleTopics: possibleTopics.trimmedNonEmptyValues(),
            importanceScore: importanceScore
        )
    }
}

private extension Array where Element == String {
    func trimmedNonEmptyValues() -> [String] {
        map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
