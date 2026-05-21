import Foundation
import RSSRadarCore

public enum RSSRadarFeeds {
    public static let moduleName = "RSSRadarFeeds"
}

public protocol FeedStore {
    func save(_ feed: Feed) throws
}

public protocol FeedDataLoader {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: FeedDataLoader {
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url, delegate: nil)
    }
}

public enum ManualFeedAddError: Error, Equatable, LocalizedError {
    case invalidURL(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            "Invalid RSS URL: \(value)"
        }
    }
}

public final class ManualFeedAddService {
    private let loader: FeedDataLoader
    private let store: FeedStore?

    public init(loader: FeedDataLoader = URLSession.shared, store: FeedStore? = nil) {
        self.loader = loader
        self.store = store
    }

    @discardableResult
    public func addFeed(urlString: String, now: Date = Date()) async throws -> Feed {
        let url = try Self.validateURL(urlString)
        let feed = await makeFeed(url: url, now: now)
        try store?.save(feed)
        return feed
    }

    private func makeFeed(url: URL, now: Date) async -> Feed {
        do {
            let data = try await loadFeedData(from: url)
            let metadata = try FeedMetadataParser().parse(data)
            return Feed(
                title: metadata.title,
                url: url,
                siteURL: metadata.siteURL,
                status: metadata.hasArticles ? .active : .noArticles,
                lastCheckedAt: now,
                lastSuccessAt: now,
                errorMessage: nil,
                createdAt: now,
                updatedAt: now
            )
        } catch {
            return Feed(
                title: Self.fallbackTitle(for: url),
                url: url,
                status: .error,
                lastCheckedAt: now,
                errorMessage: Self.safeErrorMessage(from: error),
                createdAt: now,
                updatedAt: now
            )
        }
    }

    private func loadFeedData(from url: URL) async throws -> Data {
        let (data, response) = try await loader.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FeedMetadataParserError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private static func validateURL(_ rawValue: String) throws -> URL {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmedValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host?.isEmpty == false
        else {
            throw ManualFeedAddError.invalidURL(rawValue)
        }
        return url
    }

    private static func fallbackTitle(for url: URL) -> String {
        url.host ?? url.absoluteString
    }

    private static func safeErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
