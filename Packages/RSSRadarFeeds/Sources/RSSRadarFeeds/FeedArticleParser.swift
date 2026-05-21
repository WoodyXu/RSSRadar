import FeedKit
import Foundation

struct FeedArticleCandidate: Equatable {
    var title: String
    var url: URL
    var author: String?
    var publishedAt: Date?
    var rssSummary: String?
    var content: String?
}

struct FeedArticleParser {
    func parse(_ data: Data) throws -> [FeedArticleCandidate] {
        let parser = FeedParser(data: data)
        let parsedFeed: FeedKit.Feed
        switch parser.parse() {
        case let .success(feed):
            parsedFeed = feed
        case let .failure(error):
            throw FeedMetadataParserError.unsupportedFeed(error.localizedDescription)
        }

        switch parsedFeed {
        case let .rss(rssFeed):
            return (rssFeed.items ?? []).compactMap(article(from:))
        case let .atom(atomFeed):
            return (atomFeed.entries ?? []).compactMap(article(from:))
        case let .json(jsonFeed):
            return (jsonFeed.items ?? []).compactMap(article(from:))
        }
    }

    private func article(from item: RSSFeedItem) -> FeedArticleCandidate? {
        guard let url = Self.articleURL(from: item.link ?? item.guid?.value) else {
            return nil
        }

        return FeedArticleCandidate(
            title: Self.title(item.title, fallbackURL: url),
            url: url,
            author: Self.nonEmpty(item.author),
            publishedAt: item.pubDate,
            rssSummary: Self.nonEmpty(item.description),
            content: Self.nonEmpty(item.content?.contentEncoded)
        )
    }

    private func article(from entry: AtomFeedEntry) -> FeedArticleCandidate? {
        guard let url = Self.articleURL(from: Self.preferredAtomLink(entry.links)) else {
            return nil
        }

        return FeedArticleCandidate(
            title: Self.title(entry.title, fallbackURL: url),
            url: url,
            author: Self.nonEmpty(entry.authors?.first?.name),
            publishedAt: entry.published ?? entry.updated,
            rssSummary: Self.nonEmpty(entry.summary?.value),
            content: Self.nonEmpty(entry.content?.value)
        )
    }

    private func article(from item: JSONFeedItem) -> FeedArticleCandidate? {
        guard let url = Self.articleURL(from: item.url ?? item.externalUrl ?? item.id) else {
            return nil
        }

        return FeedArticleCandidate(
            title: Self.title(item.title ?? item.summary, fallbackURL: url),
            url: url,
            author: Self.nonEmpty(item.author?.name),
            publishedAt: item.datePublished ?? item.dateModified,
            rssSummary: Self.nonEmpty(item.summary),
            content: Self.nonEmpty(item.contentHtml) ?? Self.nonEmpty(item.contentText)
        )
    }

    private static func preferredAtomLink(_ links: [AtomFeedEntryLink]?) -> String? {
        guard let links else {
            return nil
        }

        return links.first { link in
            let rel = link.attributes?.rel?.lowercased()
            return rel == nil || rel == "alternate"
        }?.attributes?.href ?? links.first?.attributes?.href
    }

    private static func articleURL(from rawValue: String?) -> URL? {
        guard let rawValue = nonEmpty(rawValue), let url = URL(string: rawValue) else {
            return nil
        }

        let scheme = url.scheme?.lowercased()
        guard ["http", "https"].contains(scheme), url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func title(_ rawValue: String?, fallbackURL: URL) -> String {
        nonEmpty(rawValue) ?? fallbackURL.absoluteString
    }

    private static func nonEmpty(_ rawValue: String?) -> String? {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return nil
        }
        return trimmedValue
    }
}
