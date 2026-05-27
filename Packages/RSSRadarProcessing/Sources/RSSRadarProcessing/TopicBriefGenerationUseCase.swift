import Foundation

import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence

public final class TopicBriefGenerationUseCase: @unchecked Sendable {
  private let repositories: RSSRadarRepositories
  private let generator: any TopicBriefGenerating
  private let articleSelectionConfig: TopicBriefArticleSelectionConfig

  public init(
    repositories: RSSRadarRepositories,
    generator: any TopicBriefGenerating,
    articleSelectionConfig: TopicBriefArticleSelectionConfig = .default
  ) {
    self.repositories = repositories
    self.generator = generator
    self.articleSelectionConfig = articleSelectionConfig
  }

  @discardableResult
  public func generateIfNeeded(
    topicID: String,
    briefType: TopicBriefType,
    modelName: String,
    generatedAt: Date = Date()
  ) async throws -> TopicBriefGenerationUseCaseResult {
    let topic = try fetchTopic(id: topicID)
    try validate(topic: topic, briefType: briefType)

    if let cachedBrief = try repositories.topicBriefs.fetch(topicID: topic.id, briefType: briefType) {
      return TopicBriefGenerationUseCaseResult(brief: cachedBrief, didGenerate: false)
    }

    try validateModelName(modelName)

    let sourceArticles = try fetchSelectedSourceArticles(
      topicID: topic.id,
      briefType: briefType
    )

    guard !sourceArticles.isEmpty else {
      throw TopicBriefGenerationUseCaseError.noAnalyzedRelatedArticles(topic.id)
    }

    let brief = try await generator.generateBrief(
      topic: topic,
      relatedArticles: sourceArticles,
      briefType: briefType,
      modelName: modelName,
      generatedAt: generatedAt
    )

    try repositories.topicBriefs.save(brief)

    try repositories.operationLogs.save(
      OperationLog(
        level: .info,
        message: "Generated TopicBrief",
        context: [
          "topic_id": topic.id,
          "brief_type": briefType.rawValue,
          "selected_article_count": "\(sourceArticles.count)"
        ],
        createdAt: generatedAt
      )
    )

    return TopicBriefGenerationUseCaseResult(brief: brief, didGenerate: true)
  }

  @discardableResult
  public func regenerate(
    topicID: String,
    briefType: TopicBriefType,
    modelName: String,
    generatedAt: Date = Date()
  ) async throws -> TopicBriefGenerationUseCaseResult {
    let topic = try fetchTopic(id: topicID)
    try validate(topic: topic, briefType: briefType)
    try validateModelName(modelName)

    let sourceArticles = try fetchSelectedSourceArticles(
      topicID: topic.id,
      briefType: briefType
    )

    guard !sourceArticles.isEmpty else {
      throw TopicBriefGenerationUseCaseError.noAnalyzedRelatedArticles(topic.id)
    }

    do {
      let brief = try await generator.generateBrief(
        topic: topic,
        relatedArticles: sourceArticles,
        briefType: briefType,
        modelName: modelName,
        generatedAt: generatedAt
      )

      try repositories.topicBriefs.save(brief)

      try repositories.operationLogs.save(
        OperationLog(
          level: .info,
          message: "Regenerated TopicBrief",
          context: [
            "topic_id": topic.id,
            "brief_type": briefType.rawValue,
            "selected_article_count": "\(sourceArticles.count)"
          ],
          createdAt: generatedAt
        )
      )

      return TopicBriefGenerationUseCaseResult(brief: brief, didGenerate: true)
    } catch {
      try repositories.operationLogs.save(
        OperationLog(
          level: .error,
          message: "Failed to regenerate TopicBrief",
          context: [
            "topic_id": topic.id,
            "brief_type": briefType.rawValue,
            "selected_article_count": "\(sourceArticles.count)"
          ],
          createdAt: generatedAt
        )
      )

      throw error
    }
  }

  private func fetchTopic(id topicID: String) throws -> Topic {
    guard let topic = try repositories.topics.fetch(id: topicID) else {
      throw TopicBriefGenerationUseCaseError.topicNotFound(topicID)
    }

    return topic
  }

  private func validate(topic: Topic, briefType: TopicBriefType) throws {
    switch (topic.status, briefType) {
    case (.active, .full), (.candidate, .preview):
      return

    case (.candidate, .full):
      throw TopicBriefGenerationUseCaseError.candidateRequiresPreview(topic.id)

    case (.active, .preview):
      throw TopicBriefGenerationUseCaseError.activeRequiresFull(topic.id)

    case (.ignored, _), (.archived, _):
      throw TopicBriefGenerationUseCaseError.unsupportedTopicStatus(topic.status)
    }
  }

  private func validateModelName(_ modelName: String) throws {
    guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TopicBriefGenerationUseCaseError.missingModelName
    }
  }

  private func fetchSelectedSourceArticles(
    topicID: String,
    briefType: TopicBriefType
  ) throws -> [TopicBriefSourceArticle] {
    let allSourceArticles = try fetchAllSourceArticles(topicID: topicID)

    return selectSourceArticles(
      allSourceArticles,
      limits: articleSelectionConfig.limits(for: briefType)
    )
  }

  private func fetchAllSourceArticles(topicID: String) throws -> [TopicBriefSourceArticle] {
    let relationships = try repositories.topicArticles.fetchForTopic(id: topicID)

    var sourceArticles: [TopicBriefSourceArticle] = []

    for relationship in relationships {
      guard let article = try repositories.articles.fetch(id: relationship.articleID),
            let analysis = try repositories.articleAnalyses.fetch(articleID: article.id) else {
        continue
      }

      let feedTitle = try repositories.feeds.fetch(id: article.feedID)?.title ?? "Unknown source"

      sourceArticles.append(
        TopicBriefSourceArticle(
          article: article,
          analysis: analysis,
          feedTitle: feedTitle,
          contributionType: relationship.contributionType
        )
      )
    }

    return sourceArticles
  }

  private func selectSourceArticles(
    _ articles: [TopicBriefSourceArticle],
    limits: TopicBriefArticleSelectionLimits
  ) -> [TopicBriefSourceArticle] {
    guard !articles.isEmpty else {
      return []
    }

    let recentArticles = articles
      .sorted(by: sortByRecencyDescending)
      .prefix(limits.recentLimit)

    let highImportanceArticles = articles
      .sorted(by: sortByImportanceDescending)
      .prefix(limits.highImportanceLimit)

    let historicalNodeArticles = selectHistoricalNodes(
      from: articles,
      limit: limits.historicalNodeLimit
    )

    let merged = mergeUniqueArticles([
      Array(recentArticles),
      Array(highImportanceArticles),
      historicalNodeArticles
    ])

    guard !merged.isEmpty else {
      return Array(
        articles
          .sorted(by: sortByRecencyDescending)
          .prefix(1)
      )
    }

    return merged.sorted(by: sortByRecencyDescending)
  }

  private func mergeUniqueArticles(
    _ groups: [[TopicBriefSourceArticle]]
  ) -> [TopicBriefSourceArticle] {
    var seenArticleIDs = Set<String>()
    var result: [TopicBriefSourceArticle] = []

    for sourceArticle in groups.flatMap({ $0 }) {
      if seenArticleIDs.insert(sourceArticle.article.id).inserted {
        result.append(sourceArticle)
      }
    }

    return result
  }

  private func selectHistoricalNodes(
    from articles: [TopicBriefSourceArticle],
    limit: Int
  ) -> [TopicBriefSourceArticle] {
    guard limit > 0 else {
      return []
    }

    let candidates = articles.filter(isHistoricalNodeCandidate)

    guard !candidates.isEmpty else {
      return []
    }

    let groupedByMonth = Dictionary(grouping: candidates) { sourceArticle in
      monthKey(for: articleSortDate(sourceArticle))
    }

    let bestArticlePerMonth = groupedByMonth.values.compactMap { bucket in
      bucket.max { lhs, rhs in
        let lhsScore = historicalNodeScore(lhs)
        let rhsScore = historicalNodeScore(rhs)

        if lhsScore == rhsScore {
          return articleSortDate(lhs) < articleSortDate(rhs)
        }

        return lhsScore < rhsScore
      }
    }

    return bestArticlePerMonth
      .sorted { lhs, rhs in
        let lhsScore = historicalNodeScore(lhs)
        let rhsScore = historicalNodeScore(rhs)

        if lhsScore == rhsScore {
          return articleSortDate(lhs) > articleSortDate(rhs)
        }

        return lhsScore > rhsScore
      }
      .prefix(limit)
      .map { $0 }
  }

  private func isHistoricalNodeCandidate(_ sourceArticle: TopicBriefSourceArticle) -> Bool {
    switch sourceArticle.contributionType {
    case .newEvent, .newData:
      return true

    case .newOpinion, .background:
      return !sourceArticle.analysis.events.isEmpty ||
        !sourceArticle.analysis.metrics.isEmpty
    }
  }

  private func historicalNodeScore(_ sourceArticle: TopicBriefSourceArticle) -> Double {
    var score = importanceScore(sourceArticle)

    switch sourceArticle.contributionType {
    case .newEvent:
      score += 0.25

    case .newData:
      score += 0.20

    case .newOpinion:
      score += 0.05

    case .background:
      break
    }

    score += min(Double(sourceArticle.analysis.events.count) * 0.05, 0.20)
    score += min(Double(sourceArticle.analysis.metrics.count) * 0.05, 0.20)

    return score
  }

  private func sortByRecencyDescending(
    _ lhs: TopicBriefSourceArticle,
    _ rhs: TopicBriefSourceArticle
  ) -> Bool {
    articleSortDate(lhs) > articleSortDate(rhs)
  }

  private func sortByImportanceDescending(
    _ lhs: TopicBriefSourceArticle,
    _ rhs: TopicBriefSourceArticle
  ) -> Bool {
    let lhsScore = importanceScore(lhs)
    let rhsScore = importanceScore(rhs)

    if lhsScore == rhsScore {
      return articleSortDate(lhs) > articleSortDate(rhs)
    }

    return lhsScore > rhsScore
  }

  private func articleSortDate(_ sourceArticle: TopicBriefSourceArticle) -> Date {
    sourceArticle.article.publishedAt ?? sourceArticle.article.createdAt
  }

  private func importanceScore(_ sourceArticle: TopicBriefSourceArticle) -> Double {
    max(
      sourceArticle.analysis.importanceScore,
      sourceArticle.article.importanceScore ?? 0
    )
  }

  private func monthKey(for date: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let components = calendar.dateComponents([.year, .month], from: date)

    let year = components.year ?? 0
    let month = components.month ?? 0

    return String(format: "%04d-%02d", year, month)
  }
}

public struct TopicBriefArticleSelectionConfig: Equatable, Sendable {
  public var full: TopicBriefArticleSelectionLimits
  public var preview: TopicBriefArticleSelectionLimits

  public init(
    full: TopicBriefArticleSelectionLimits,
    preview: TopicBriefArticleSelectionLimits
  ) {
    self.full = full
    self.preview = preview
  }

  public static let `default` = TopicBriefArticleSelectionConfig(
    full: TopicBriefArticleSelectionLimits(
      recentLimit: 12,
      highImportanceLimit: 8,
      historicalNodeLimit: 8
    ),
    preview: TopicBriefArticleSelectionLimits(
      recentLimit: 6,
      highImportanceLimit: 4,
      historicalNodeLimit: 3
    )
  )

  public func limits(for briefType: TopicBriefType) -> TopicBriefArticleSelectionLimits {
    switch briefType {
    case .full:
      full

    case .preview:
      preview
    }
  }
}

public struct TopicBriefArticleSelectionLimits: Equatable, Sendable {
  public var recentLimit: Int
  public var highImportanceLimit: Int
  public var historicalNodeLimit: Int

  public init(
    recentLimit: Int,
    highImportanceLimit: Int,
    historicalNodeLimit: Int
  ) {
    self.recentLimit = max(0, recentLimit)
    self.highImportanceLimit = max(0, highImportanceLimit)
    self.historicalNodeLimit = max(0, historicalNodeLimit)
  }
}

public struct TopicBriefGenerationUseCaseResult: Equatable, Sendable {
  public var brief: TopicBrief
  public var didGenerate: Bool

  public init(brief: TopicBrief, didGenerate: Bool) {
    self.brief = brief
    self.didGenerate = didGenerate
  }
}

public enum TopicBriefGenerationUseCaseError: Error, Equatable, LocalizedError {
  case topicNotFound(String)
  case missingModelName
  case activeRequiresFull(String)
  case candidateRequiresPreview(String)
  case unsupportedTopicStatus(TopicStatus)
  case noAnalyzedRelatedArticles(String)

  public var errorDescription: String? {
    switch self {
    case let .topicNotFound(topicID):
      "Topic was not found for TopicBrief generation: \(topicID)."

    case .missingModelName:
      "AI model name is not configured for TopicBrief generation."

    case let .activeRequiresFull(topicID):
      "Active topic requires a full TopicBrief: \(topicID)."

    case let .candidateRequiresPreview(topicID):
      "Candidate topic requires a preview TopicBrief: \(topicID)."

    case let .unsupportedTopicStatus(status):
      "Topic status is not supported for TopicBrief generation: \(status.rawValue)."

    case let .noAnalyzedRelatedArticles(topicID):
      "Topic has no analyzed related articles for TopicBrief generation: \(topicID)."
    }
  }
}