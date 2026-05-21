import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence

public final class ArticleAnalysisUseCase: @unchecked Sendable {
    private let repositories: RSSRadarRepositories
    private let analyzer: any ArticleAnalyzing

    public init(
        repositories: RSSRadarRepositories,
        analyzer: any ArticleAnalyzing
    ) {
        self.repositories = repositories
        self.analyzer = analyzer
    }

    @discardableResult
    public func analyzeArticle(
        id articleID: String,
        modelName: String,
        generatedAt: Date = Date()
    ) async throws -> ArticleAnalysis {
        guard var article = try repositories.articles.fetch(id: articleID) else {
            throw ArticleAnalysisUseCaseError.articleNotFound(articleID)
        }

        let feed = try repositories.feeds.fetch(id: article.feedID)
        let sourceTitle = feed?.title ?? ""
        let analysis = try await analyzer.analyze(
            article: article,
            sourceTitle: sourceTitle,
            modelName: modelName,
            generatedAt: generatedAt
        )

        article.status = .analyzed
        article.importanceScore = analysis.importanceScore
        article.errorMessage = nil
        article.updatedAt = generatedAt

        try repositories.performTransaction { transaction in
            try transaction.articleAnalyses.save(analysis)
            try transaction.articles.save(article)
        }

        return analysis
    }
}

public enum ArticleAnalysisUseCaseError: Error, Equatable, LocalizedError {
    case articleNotFound(String)
    case missingModelName

    public var errorDescription: String? {
        switch self {
        case let .articleNotFound(articleID):
            "Article was not found for analysis: \(articleID)"
        case .missingModelName:
            "AI model name is not configured for article analysis."
        }
    }
}
