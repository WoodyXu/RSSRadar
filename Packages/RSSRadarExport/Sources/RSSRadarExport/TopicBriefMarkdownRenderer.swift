import Foundation
import RSSRadarCore
import RSSRadarProcessing

public struct TopicBriefMarkdownRenderer: Sendable {
    public init() {}

    public func render(snapshot: TopicDetailSnapshot) throws -> String {
        guard let brief = snapshot.brief else {
            throw TopicBriefMarkdownRendererError.missingBrief(snapshot.topic.id)
        }

        var sections: [String] = []
        sections.append("# \(snapshot.topic.name)")
        sections.append("生成时间：\(formatDate(brief.generatedAt))")
        sections.append(section(title: "当前结论", body: brief.currentTakeaway))
        sections.append(section(title: "最近发生了什么", body: latestChangesMarkdown(snapshot.latestChanges)))
        sections.append(section(title: "时间线", body: timelineMarkdown(snapshot.timeline)))
        sections.append(section(title: "主要观点分歧", body: viewpointsMarkdown(snapshot.viewpoints)))
        sections.append(section(title: "关键证据", body: evidenceMarkdown(snapshot.evidence)))
        sections.append(section(title: "接下来值得观察", body: questionsMarkdown(snapshot.questionsToWatch)))
        sections.append(section(title: "相关文章", body: relatedArticlesMarkdown(snapshot.relatedArticles)))

        return sections.joined(separator: "\n\n") + "\n"
    }

    private func section(title: String, body: String) -> String {
        "## \(title)\n\n\(body)"
    }

    private func latestChangesMarkdown(_ changes: [TopicBriefChange]) -> String {
        guard !changes.isEmpty else {
            return emptyPlaceholder
        }
        return changes.map { "- \(escapeLine($0.text))" }.joined(separator: "\n")
    }

    private func timelineMarkdown(_ items: [TopicBriefTimelineItem]) -> String {
        guard !items.isEmpty else {
            return emptyPlaceholder
        }
        return items.map { item in
            let datePrefix = item.date.map { "\(formatDate($0)) - " } ?? ""
            return "- \(datePrefix)\(escapeLine(item.title))：\(escapeLine(item.description))"
        }.joined(separator: "\n")
    }

    private func viewpointsMarkdown(_ viewpoints: [TopicBriefViewpoint]) -> String {
        guard !viewpoints.isEmpty else {
            return emptyPlaceholder
        }
        return viewpoints.map { "- **\(escapeInline($0.title))**：\(escapeLine($0.summary))" }.joined(separator: "\n")
    }

    private func evidenceMarkdown(_ evidenceItems: [TopicDetailEvidence]) -> String {
        guard !evidenceItems.isEmpty else {
            return emptyPlaceholder
        }
        return evidenceItems.map { item in
            let evidence = item.evidence
            let sourceTitle = item.sourceArticle?.title ?? evidence.sourceArticleTitle
            let sourceURL = item.sourceArticle?.url ?? evidence.sourceURL
            let publishedAt = (item.sourceArticle?.publishedAt ?? evidence.publishedAt)
                .map { "，\(formatDate($0))" } ?? ""
            let source = "来源：[\(escapeLinkText(sourceTitle))](\(sourceURL.absoluteString))"
            return "- \(escapeLine(evidence.content))（\(source)，\(escapeLine(item.sourceName))\(publishedAt)）"
        }.joined(separator: "\n")
    }

    private func questionsMarkdown(_ questions: [String]) -> String {
        guard !questions.isEmpty else {
            return emptyPlaceholder
        }
        return questions.map { "- \(escapeLine($0))" }.joined(separator: "\n")
    }

    private func relatedArticlesMarkdown(_ articles: [TopicDetailArticle]) -> String {
        guard !articles.isEmpty else {
            return emptyPlaceholder
        }
        return articles.map { article in
            let source = article.sourceName.map { "，来源：\(escapeLine($0))" } ?? ""
            let publishedAt = article.article.publishedAt.map { "，发布时间：\(formatDate($0))" } ?? ""
            let contribution = article.contributionType.map { "，贡献：\($0.rawValue)" } ?? ""
            let summary = article.analysisSummary.map { "\n  - 摘要：\(escapeLine($0))" } ?? ""
            let link = "[\(escapeLinkText(article.article.title))](\(article.article.url.absoluteString))"
            return "- \(link)\(source)\(publishedAt)\(contribution)\(summary)"
        }.joined(separator: "\n")
    }

    private func escapeLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escapeInline(_ text: String) -> String {
        escapeLine(text).replacingOccurrences(of: "**", with: "\\*\\*")
    }

    private func escapeLinkText(_ text: String) -> String {
        escapeLine(text)
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private var emptyPlaceholder: String {
        "暂无。"
    }
}

public enum TopicBriefMarkdownRendererError: Error, Equatable, LocalizedError {
    case missingBrief(String)

    public var errorDescription: String? {
        switch self {
        case let .missingBrief(topicID):
            "TopicBrief cache is missing for Markdown export: \(topicID)."
        }
    }
}
