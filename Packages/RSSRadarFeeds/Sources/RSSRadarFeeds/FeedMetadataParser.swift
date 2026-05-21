import FeedKit
import Foundation

struct FeedMetadata: Equatable {
    var title: String
    var siteURL: URL?
    var hasArticles: Bool
}

enum FeedMetadataParserError: Error, Equatable, LocalizedError {
    case emptyTitle
    case httpStatus(Int)
    case unsupportedFeed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Feed title is missing"
        case let .httpStatus(statusCode):
            "Feed request failed with HTTP status \(statusCode)"
        case let .unsupportedFeed(reason):
            "Feed parsing failed: \(reason)"
        }
    }
}

struct FeedMetadataParser {
    func parse(_ data: Data) throws -> FeedMetadata {
        let parser = FeedParser(data: data)
        let feed: Feed
        switch parser.parse() {
        case let .success(parsedFeed):
            feed = parsedFeed
        case let .failure(error):
            throw FeedMetadataParserError.unsupportedFeed(error.localizedDescription)
        }

        switch feed {
        case let .rss(rssFeed):
            return try metadata(
                title: rssFeed.title,
                siteURLString: rssFeed.link,
                itemCount: rssFeed.items?.count ?? 0
            )
        case let .atom(atomFeed):
            return try metadata(
                title: atomFeed.title,
                siteURLString: atomFeed.links?.first?.attributes?.href,
                itemCount: atomFeed.entries?.count ?? 0
            )
        case let .json(jsonFeed):
            return try metadata(
                title: jsonFeed.title,
                siteURLString: jsonFeed.homePageURL,
                itemCount: jsonFeed.items?.count ?? 0
            )
        }
    }

    private func metadata(title: String?, siteURLString: String?, itemCount: Int) throws -> FeedMetadata {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedTitle, !trimmedTitle.isEmpty else {
            throw FeedMetadataParserError.emptyTitle
        }

        return FeedMetadata(
            title: trimmedTitle,
            siteURL: siteURL(from: siteURLString),
            hasArticles: itemCount > 0
        )
    }

    private func siteURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return URL(string: trimmedValue)
    }
}
