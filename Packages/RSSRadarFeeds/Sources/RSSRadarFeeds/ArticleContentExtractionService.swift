import Foundation
import RSSRadarCore
import SwiftSoup

public struct ArticleContentExtractionService {
    private let loader: FeedDataLoader

    public init(loader: FeedDataLoader = URLSession.shared) {
        self.loader = loader
    }

    public func extractContent(for article: Article, now: Date = Date()) async -> Article {
        if let fullContent = Self.normalizedText(from: article.content) {
            return parsedArticle(article, content: fullContent, source: .rssFullContent, now: now)
        }

        if let webContent = await webExtractedContent(from: article.url) {
            return parsedArticle(article, content: webContent, source: .webExtracted, now: now)
        }

        return parsedArticle(
            article,
            content: Self.normalizedText(from: article.rssSummary),
            source: .rssSummary,
            now: now
        )
    }

    private func webExtractedContent(from url: URL) async -> String? {
        do {
            let (data, response) = try await loader.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }
            return try WebArticleExtractor.extract(fromHTML: html)
        } catch {
            return nil
        }
    }

    private func parsedArticle(
        _ article: Article,
        content: String?,
        source: ArticleContentSource,
        now: Date
    ) -> Article {
        Article(
            id: article.id,
            feedID: article.feedID,
            title: article.title,
            url: article.url,
            author: article.author,
            publishedAt: article.publishedAt,
            rssSummary: article.rssSummary,
            content: content,
            contentSource: source,
            status: .parsed,
            importanceScore: article.importanceScore,
            errorMessage: article.errorMessage,
            createdAt: article.createdAt,
            updatedAt: now
        )
    }

    private static func normalizedText(from rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let parsedText = (try? SwiftSoup.parse(rawValue).text()) ?? rawValue
        let normalized = parsedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum WebArticleExtractor {
    private static let minimumBodyLength = 80
    private static let bodySelectors = [
        "article",
        "main",
        "[role=main]",
        ".post-content",
        ".entry-content",
        ".article-content",
        ".content"
    ]

    static func extract(fromHTML html: String) throws -> String? {
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, nav, header, footer, aside, noscript, svg, form").remove()

        if let selectedText = try bestText(fromSelectorsIn: document) {
            return selectedText
        }

        return try paragraphText(from: document)
    }

    private static func bestText(fromSelectorsIn document: Document) throws -> String? {
        var bestText: String?
        var bestScore = 0

        for selector in bodySelectors {
            for element in try document.select(selector).array() {
                guard let candidate = try normalizedText(from: element) else {
                    continue
                }
                let score = candidate.count + paragraphCount(in: element) * 80 - linkTextLength(in: element)
                if score > bestScore {
                    bestScore = score
                    bestText = candidate
                }
            }
        }

        guard let bestText, bestText.count >= minimumBodyLength else {
            return nil
        }
        return bestText
    }

    private static func paragraphText(from document: Document) throws -> String? {
        let paragraphs = try document.select("p").array().compactMap { element -> String? in
            try normalizedText(from: element)
        }
        let text = paragraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minimumBodyLength else {
            return nil
        }
        return text
    }

    private static func normalizedText(from element: Element) throws -> String? {
        let text = try element.text()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func paragraphCount(in element: Element) -> Int {
        (try? element.select("p").array().count) ?? 0
    }

    private static func linkTextLength(in element: Element) -> Int {
        ((try? element.select("a").array()) ?? []).reduce(0) { partialResult, link in
            partialResult + ((try? link.text().count) ?? 0)
        }
    }
}
