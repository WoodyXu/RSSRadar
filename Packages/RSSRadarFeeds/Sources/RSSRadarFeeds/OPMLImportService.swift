import Foundation
import RSSRadarCore

public protocol OPMLFeedStore {
    func fetchAll() throws -> [Feed]
    func save(_ feed: Feed) throws
}

public struct OPMLImportResult: Equatable {
    public var importedFeeds: [Feed]
    public var skippedDuplicates: [OPMLSkippedDuplicate]
    public var errors: [OPMLImportErrorRecord]

    public init(
        importedFeeds: [Feed] = [],
        skippedDuplicates: [OPMLSkippedDuplicate] = [],
        errors: [OPMLImportErrorRecord] = []
    ) {
        self.importedFeeds = importedFeeds
        self.skippedDuplicates = skippedDuplicates
        self.errors = errors
    }
}

public struct OPMLSkippedDuplicate: Equatable {
    public var title: String
    public var xmlURL: URL

    public init(title: String, xmlURL: URL) {
        self.title = title
        self.xmlURL = xmlURL
    }
}

public struct OPMLImportErrorRecord: Equatable {
    public var title: String?
    public var reason: String

    public init(title: String?, reason: String) {
        self.title = title
        self.reason = reason
    }
}

public enum OPMLImportError: Error, Equatable, LocalizedError {
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDocument(reason):
            "OPML parsing failed: \(reason)"
        }
    }
}

public final class OPMLImportService {
    private let store: OPMLFeedStore?

    public init(store: OPMLFeedStore? = nil) {
        self.store = store
    }

    @discardableResult
    public func importOPML(data: Data, now: Date = Date()) throws -> OPMLImportResult {
        let outlines = try OPMLParser().parse(data)
        var result = OPMLImportResult()
        var seenURLs = Set(try existingFeedURLKeys())

        for outline in outlines where outline.isFeedCandidate {
            guard let xmlURLString = outline.xmlURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !xmlURLString.isEmpty else {
                result.errors.append(OPMLImportErrorRecord(title: outline.displayTitle, reason: "Missing xmlUrl"))
                continue
            }

            guard let xmlURL = Self.feedURL(from: xmlURLString) else {
                result.errors.append(OPMLImportErrorRecord(title: outline.displayTitle, reason: "Invalid xmlUrl"))
                continue
            }

            let urlKey = Self.urlKey(xmlURL)
            let title = Self.feedTitle(for: outline, xmlURL: xmlURL)
            if seenURLs.contains(urlKey) {
                result.skippedDuplicates.append(OPMLSkippedDuplicate(title: title, xmlURL: xmlURL))
                continue
            }

            let feed = Feed(
                title: title,
                url: xmlURL,
                siteURL: Self.siteURL(from: outline.htmlURLString),
                status: .active,
                createdAt: now,
                updatedAt: now
            )
            try store?.save(feed)
            result.importedFeeds.append(feed)
            seenURLs.insert(urlKey)
        }

        return result
    }

    private func existingFeedURLKeys() throws -> [String] {
        try store?.fetchAll().map { Self.urlKey($0.url) } ?? []
    }

    private static func feedURL(from rawValue: String) -> URL? {
        guard
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func siteURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return URL(string: trimmedValue)
    }

    private static func feedTitle(for outline: OPMLOutline, xmlURL: URL) -> String {
        if let displayTitle = outline.displayTitle {
            return displayTitle
        }
        return xmlURL.host ?? xmlURL.absoluteString
    }

    private static func urlKey(_ url: URL) -> String {
        url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct OPMLOutline: Equatable {
    var text: String?
    var title: String?
    var xmlURLString: String?
    var htmlURLString: String?
    var hasChildren: Bool = false

    var displayTitle: String? {
        let preferredTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferredTitle, !preferredTitle.isEmpty {
            return preferredTitle
        }

        let fallbackText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }

        return nil
    }

    var isFeedCandidate: Bool {
        xmlURLString != nil || !hasChildren
    }
}

private final class OPMLParser: NSObject, XMLParserDelegate {
    private var outlineStack: [OPMLOutline] = []
    private var completedOutlines: [OPMLOutline] = []
    private var parserError: Error?

    func parse(_ data: Data) throws -> [OPMLOutline] {
        outlineStack = []
        completedOutlines = []
        parserError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            let reason = parser.parserError?.localizedDescription ?? "Invalid XML document"
            throw OPMLImportError.invalidDocument(reason)
        }

        if let parserError {
            throw parserError
        }

        return completedOutlines
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else {
            return
        }

        if let lastIndex = outlineStack.indices.last {
            outlineStack[lastIndex].hasChildren = true
        }

        outlineStack.append(OPMLOutline(
            text: attributeDict["text"],
            title: attributeDict["title"],
            xmlURLString: attributeDict["xmlUrl"],
            htmlURLString: attributeDict["htmlUrl"]
        ))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName.lowercased() == "outline", let outline = outlineStack.popLast() else {
            return
        }

        completedOutlines.append(outline)
    }
}
