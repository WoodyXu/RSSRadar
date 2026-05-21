import AppKit
import Foundation
import RSSRadarProcessing

public protocol MarkdownClipboardWriting: Sendable {
    func writeMarkdown(_ markdown: String) throws
}

public struct SystemMarkdownClipboardWriter: MarkdownClipboardWriting {
    public init() {}

    public func writeMarkdown(_ markdown: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(markdown, forType: .string) else {
            throw TopicBriefMarkdownExportError.clipboardWriteFailed
        }
    }
}
public final class TopicBriefMarkdownExportService: @unchecked Sendable {
    private let renderer: TopicBriefMarkdownRenderer
    private let clipboardWriter: any MarkdownClipboardWriting
    private let fileManager: FileManager

    public init(
        renderer: TopicBriefMarkdownRenderer = TopicBriefMarkdownRenderer(),
        clipboardWriter: any MarkdownClipboardWriting = SystemMarkdownClipboardWriter(),
        fileManager: FileManager = .default
    ) {
        self.renderer = renderer
        self.clipboardWriter = clipboardWriter
        self.fileManager = fileManager
    }

    @discardableResult
    public func copyMarkdown(snapshot: TopicDetailSnapshot) throws -> String {
        let markdown = try renderer.render(snapshot: snapshot)
        try clipboardWriter.writeMarkdown(markdown)
        return markdown
    }

    @discardableResult
    public func exportMarkdown(snapshot: TopicDetailSnapshot, to fileURL: URL) throws -> String {
        guard fileURL.pathExtension.lowercased() == "md" else {
            throw TopicBriefMarkdownExportError.invalidFileExtension(fileURL.pathExtension)
        }

        let markdown = try renderer.render(snapshot: snapshot)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return markdown
    }
}

public enum TopicBriefMarkdownExportError: Error, Equatable, LocalizedError {
    case clipboardWriteFailed
    case invalidFileExtension(String)

    public var errorDescription: String? {
        switch self {
        case .clipboardWriteFailed:
            "Markdown could not be copied to the clipboard."
        case let .invalidFileExtension(fileExtension):
            "Markdown export requires a .md file path, but got .\(fileExtension)."
        }
    }
}
