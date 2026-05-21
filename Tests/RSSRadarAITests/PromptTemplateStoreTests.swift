import Foundation
@testable import RSSRadarAI
import XCTest

final class PromptTemplateStoreTests: XCTestCase {
    func testLoadsEveryBuiltInPromptTemplate() throws {
        let store = PromptTemplateStore()

        for kind in PromptTemplateKind.allCases {
            let template = try store.load(kind)

            XCTAssertEqual(template.kind, kind)
            XCTAssertFalse(template.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(template.content.contains("Return this JSON object"))
        }
    }

    func testArticleAnalysisTemplateCanRenderExpectedInputs() throws {
        let template = try PromptTemplateStore().load(.articleAnalysis)
        let rendered = try template.render(variables: [
            "title": "Test title",
            "source": "Example Feed",
            "published_at": "2026-05-21T10:00:00Z",
            "url": "https://example.com/article",
            "rss_summary": "Short summary",
            "content": "Full article content"
        ])

        XCTAssertTrue(rendered.contains("Test title"))
        XCTAssertTrue(rendered.contains("Example Feed"))
        XCTAssertTrue(rendered.contains("\"possible_topics\""))
        XCTAssertFalse(rendered.contains("{{title}}"))
    }

    func testMissingTemplateReturnsClearError() {
        let store = PromptTemplateStore(bundle: Bundle(for: EmptyBundleMarker.self))

        do {
            _ = try store.load(.topicBrief)
            XCTFail("Expected missing template error")
        } catch PromptTemplateError.missingTemplate("TopicBriefPrompt") {
            XCTAssertEqual(
                PromptTemplateError.missingTemplate("TopicBriefPrompt").errorDescription,
                "Prompt template is missing: TopicBriefPrompt.md"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenderingRejectsSensitivePromptInput() throws {
        let template = try PromptTemplateStore().load(.topicAssignment)

        do {
            _ = try template.render(variables: [
                "article_analyses_json": "[]",
                "existing_topics_json": "{\"api_key\":\"sk-secret\"}"
            ])
            XCTFail("Expected sensitive input rejection")
        } catch PromptTemplateError.sensitiveInput("existing_topics_json") {
            XCTAssertEqual(
                PromptTemplateError.sensitiveInput("existing_topics_json").errorDescription,
                "Prompt input contains sensitive material and was rejected: existing_topics_json"
            )
        }
    }
}

private final class EmptyBundleMarker {}
