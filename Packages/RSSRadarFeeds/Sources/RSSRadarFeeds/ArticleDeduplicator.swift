import Foundation
import RSSRadarCore

public struct ArticleDeduplicator {
    public static let defaultTitleSimilarityThreshold = 0.92

    private let titleSimilarityThreshold: Double

    public init(titleSimilarityThreshold: Double = Self.defaultTitleSimilarityThreshold) {
        self.titleSimilarityThreshold = titleSimilarityThreshold
    }

    public func deduplicate(_ articles: [Article], existingArticles: [Article] = []) -> [Article] {
        var seenCanonicalURLs = Set(existingArticles.map { Self.canonicalURLString(for: $0.url) })
        var seenTitleKeysByFeedID = Dictionary(grouping: existingArticles, by: \.feedID)
            .mapValues { articles in articles.map { Self.titleKey(for: $0.title) } }
        var keptArticles: [Article] = []

        for article in articles {
            let canonicalURL = Self.canonicalURLString(for: article.url)
            if seenCanonicalURLs.contains(canonicalURL) {
                continue
            }

            let titleKey = Self.titleKey(for: article.title)
            let existingTitleKeys = seenTitleKeysByFeedID[article.feedID, default: []]
            let hasSimilarTitle = existingTitleKeys.contains {
                Self.areSimilar($0, titleKey, threshold: titleSimilarityThreshold)
            }
            if hasSimilarTitle {
                continue
            }

            keptArticles.append(article)
            seenCanonicalURLs.insert(canonicalURL)
            seenTitleKeysByFeedID[article.feedID, default: []].append(titleKey)
        }

        return keptArticles
    }

    public static func canonicalURLString(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil

        let filteredQueryItems = (components.queryItems ?? [])
            .filter { !isTrackingQueryItem($0) }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return (lhs.value ?? "") < (rhs.value ?? "")
                }
                return lhs.name < rhs.name
            }
        components.queryItems = filteredQueryItems.isEmpty ? nil : filteredQueryItems

        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func isTrackingQueryItem(_ item: URLQueryItem) -> Bool {
        let name = item.name.lowercased()
        return name.hasPrefix("utm_") || trackingQueryItemNames.contains(name)
    }

    private static let trackingQueryItemNames: Set<String> = [
        "fbclid",
        "gclid",
        "gbraid",
        "wbraid",
        "mc_cid",
        "mc_eid",
        "igshid",
        "yclid",
        "_hsenc",
        "_hsmi",
        "spm",
        "mkt_tok"
    ]

    private static func titleKey(for title: String) -> String {
        title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func areSimilar(_ lhs: String, _ rhs: String, threshold: Double) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return lhs == rhs
        }
        if lhs == rhs {
            return true
        }

        let tokenScore = jaccardSimilarity(
            lhsTokens: Set(lhs.split(separator: " ")),
            rhsTokens: Set(rhs.split(separator: " "))
        )
        if tokenScore >= min(threshold, 0.82) {
            return true
        }

        return editSimilarity(lhs, rhs) >= threshold
    }

    private static func jaccardSimilarity(lhsTokens: Set<Substring>, rhsTokens: Set<Substring>) -> Double {
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return lhsTokens == rhsTokens ? 1 : 0
        }
        let intersectionCount = lhsTokens.intersection(rhsTokens).count
        let unionCount = lhsTokens.union(rhsTokens).count
        return Double(intersectionCount) / Double(unionCount)
    }

    private static func editSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else {
            return 1
        }
        return 1 - (Double(levenshteinDistance(lhs, rhs)) / Double(maxLength))
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)

        if lhsCharacters.isEmpty {
            return rhsCharacters.count
        }
        if rhsCharacters.isEmpty {
            return lhsCharacters.count
        }

        var previousRow = Array(0...rhsCharacters.count)
        var currentRow = Array(repeating: 0, count: rhsCharacters.count + 1)

        for lhsIndex in 1...lhsCharacters.count {
            currentRow[0] = lhsIndex
            for rhsIndex in 1...rhsCharacters.count {
                let substitutionCost = lhsCharacters[lhsIndex - 1] == rhsCharacters[rhsIndex - 1] ? 0 : 1
                currentRow[rhsIndex] = min(
                    previousRow[rhsIndex] + 1,
                    currentRow[rhsIndex - 1] + 1,
                    previousRow[rhsIndex - 1] + substitutionCost
                )
            }
            previousRow = currentRow
        }

        return previousRow[rhsCharacters.count]
    }
}
