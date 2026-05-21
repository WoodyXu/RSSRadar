import Foundation
import RSSRadarCore
import RSSRadarExport
import RSSRadarProcessing
import XCTest

final class TopicBriefMarkdownExportTests: XCTestCase {
    func testRendererIncludesTopicBriefSectionsAndRelatedArticleLinks() throws {
        let markdown = try TopicBriefMarkdownRenderer().render(snapshot: exportSnapshot())

        XCTAssertTrue(markdown.contains("# Claude Code performance in large Swift codebases"))
        XCTAssertTrue(markdown.contains("生成时间：2023-11-17T05:46:40Z"))
        XCTAssertTrue(markdown.contains("## 当前结论"))
        XCTAssertTrue(markdown.contains("Claude Code is becoming more useful for large Swift refactors."))
        XCTAssertTrue(markdown.contains("## 最近发生了什么"))
        XCTAssertTrue(markdown.contains("- Teams reported better multi-file edit reliability."))
        XCTAssertTrue(markdown.contains("## 时间线"))
        XCTAssertTrue(markdown.contains("Pilot expanded：A Swift team expanded its Claude Code pilot."))
        XCTAssertTrue(markdown.contains("## 主要观点分歧"))
        XCTAssertTrue(markdown.contains("- **Optimistic teams**：Some teams report faster setup and onboarding."))
        XCTAssertTrue(markdown.contains("## 关键证据"))
        XCTAssertTrue(markdown.contains("The pilot reported 30% faster setup."))
        XCTAssertTrue(markdown.contains("[Claude Code adoption update](https://example.com/article-main)"))
        XCTAssertTrue(markdown.contains("## 接下来值得观察"))
        XCTAssertTrue(markdown.contains("- Whether gains persist after onboarding."))
        XCTAssertTrue(markdown.contains("## 相关文章"))
        XCTAssertTrue(markdown.contains("[Developers debate AI refactoring](https://example.com/article-extra)"))
        XCTAssertTrue(markdown.contains("摘要：Developers remain split on AI-assisted refactoring quality."))
    }

    func testCopyMarkdownWritesRenderedMarkdownToClipboardBoundary() throws {
        let clipboard = RecordingClipboardWriter()
        let service = TopicBriefMarkdownExportService(clipboardWriter: clipboard)

        let markdown = try service.copyMarkdown(snapshot: exportSnapshot())

        XCTAssertEqual(clipboard.markdown, markdown)
        XCTAssertTrue(markdown.contains("## 相关文章"))
    }

    func testExportMarkdownWritesSingleMarkdownFile() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarExportTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("topic.md")
        let service = TopicBriefMarkdownExportService(clipboardWriter: RecordingClipboardWriter())

        let markdown = try service.exportMarkdown(snapshot: exportSnapshot(), to: fileURL)
        let persistedMarkdown = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertEqual(persistedMarkdown, markdown)
        XCTAssertTrue(persistedMarkdown.contains("# Claude Code performance in large Swift codebases"))
    }

    func testRendererThrowsWhenBriefCacheIsMissing() {
        var snapshot = exportSnapshot()
        snapshot.brief = nil
        let renderer = TopicBriefMarkdownRenderer()

        XCTAssertThrowsError(try renderer.render(snapshot: snapshot)) { error in
            XCTAssertEqual(error as? TopicBriefMarkdownRendererError, .missingBrief("topic-export"))
        }
    }

    func testExportRejectsNonMarkdownFileExtension() {
        let service = TopicBriefMarkdownExportService(clipboardWriter: RecordingClipboardWriter())
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("topic.txt")

        XCTAssertThrowsError(try service.exportMarkdown(snapshot: exportSnapshot(), to: fileURL)) { error in
            XCTAssertEqual(error as? TopicBriefMarkdownExportError, .invalidFileExtension("txt"))
        }
    }
}

private final class RecordingClipboardWriter: MarkdownClipboardWriting, @unchecked Sendable {
    private(set) var markdown: String?

    func writeMarkdown(_ markdown: String) throws {
        self.markdown = markdown
    }
}

private func exportSnapshot() -> TopicDetailSnapshot {
    let topic = Topic(
        id: "topic-export",
        name: "Claude Code performance in large Swift codebases",
        description: "Tracks Claude Code behavior on large Swift projects.",
        status: .active,
        createdAt: exportDate,
        updatedAt: exportDate
    )
    let brief = TopicBrief(
        id: "brief-export",
        topicID: topic.id,
        briefType: .full,
        currentTakeaway: "Claude Code is becoming more useful for large Swift refactors.",
        latestChanges: [
            TopicBriefChange(text: "Teams reported better multi-file edit reliability.", articleIDs: ["article-main"])
        ],
        timeline: [
            TopicBriefTimelineItem(
                date: exportDate,
                title: "Pilot expanded",
                description: "A Swift team expanded its Claude Code pilot.",
                articleIDs: ["article-main"]
            )
        ],
        viewpoints: [
            TopicBriefViewpoint(
                title: "Optimistic teams",
                summary: "Some teams report faster setup and onboarding.",
                articleIDs: ["article-main"]
            )
        ],
        evidence: [
            TopicBriefEvidence(
                content: "The pilot reported 30% faster setup.",
                sourceArticleID: "article-main",
                sourceArticleTitle: "Claude Code adoption update",
                sourceName: "Engineering Blog",
                sourceURL: URL(string: "https://example.com/article-main")!,
                publishedAt: exportDate
            )
        ],
        questionsToWatch: ["Whether gains persist after onboarding."],
        relatedArticleIDs: ["article-main", "article-extra"],
        modelName: "gpt-test",
        generatedAt: exportDate
    )

    return TopicDetailSnapshot(
        topic: topic,
        briefType: .full,
        brief: brief,
        currentTakeaway: brief.currentTakeaway,
        latestChanges: brief.latestChanges,
        timeline: brief.timeline,
        viewpoints: brief.viewpoints,
        evidence: exportEvidence(),
        questionsToWatch: brief.questionsToWatch,
        relatedArticles: exportRelatedArticles()
    )
}

private func exportEvidence() -> [TopicDetailEvidence] {
    [
        TopicDetailEvidence(
            evidence: TopicBriefEvidence(
                content: "The pilot reported 30% faster setup.",
                sourceArticleID: "article-main",
                sourceArticleTitle: "Claude Code adoption update",
                sourceName: "Engineering Blog",
                sourceURL: URL(string: "https://example.com/article-main")!,
                publishedAt: exportDate
            ),
            sourceArticle: exportArticle(id: "article-main", title: "Claude Code adoption update"),
            sourceName: "Engineering Blog",
            analysisSummary: "Claude Code adoption improved in a large Swift codebase.",
            contributionType: .newData
        )
    ]
}

private func exportRelatedArticles() -> [TopicDetailArticle] {
    [
        TopicDetailArticle(
            article: exportArticle(id: "article-main", title: "Claude Code adoption update"),
            sourceName: "Engineering Blog",
            analysisSummary: "Claude Code adoption improved in a large Swift codebase.",
            contributionType: .newData,
            relationshipReason: "Provides concrete metrics for the topic.",
            confidence: 0.93
        ),
        TopicDetailArticle(
            article: exportArticle(id: "article-extra", title: "Developers debate AI refactoring"),
            sourceName: "Engineering Blog",
            analysisSummary: "Developers remain split on AI-assisted refactoring quality.",
            contributionType: .newOpinion,
            relationshipReason: "Adds a different practitioner viewpoint.",
            confidence: 0.78
        )
    ]
}

private func exportArticle(id: String, title: String) -> Article {
    Article(
        id: id,
        feedID: "feed-export",
        title: title,
        url: URL(string: "https://example.com/\(id)")!,
        publishedAt: exportDate,
        status: .assigned,
        createdAt: exportDate,
        updatedAt: exportDate
    )
}

private let exportDate = Date(timeIntervalSince1970: 1_700_200_000)
