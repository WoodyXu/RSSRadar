import Foundation
import RSSRadarCore
@testable import RSSRadarAI
import XCTest

final class ArticleAnalysisServiceTests: XCTestCase {
    func testAnalyzeArticleParsesValidAIJSONFixture() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "article-analysis", withExtension: "json"))
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let provider = RecordingAIProvider(response: AIProviderResponse(text: fixture, model: "gpt-fixture"))
        let service = ArticleAnalysisService(provider: provider)
        let article = Article(
            id: "article-1",
            feedID: "feed-1",
            title: "OpenAI improves local-first API workflow",
            url: URL(string: "https://example.com/openai-local-first")!,
            publishedAt: fixedDate,
            rssSummary: "OpenAI announced a local-first workflow.",
            content: "The workflow keeps user data local and sends selected text to the configured AI provider.",
            status: .parsed,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let analysis = try await service.analyze(
            article: article,
            sourceTitle: "Example Feed",
            modelName: "gpt-test",
            generatedAt: fixedDate
        )
        let requests = await provider.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(analysis.articleID, "article-1")
        XCTAssertEqual(
            analysis.summary,
            "OpenAI released a new local-first API workflow that reduces setup friction for Mac developers."
        )
        XCTAssertEqual(analysis.keyPoints.count, 2)
        XCTAssertEqual(analysis.entities, ["OpenAI", "macOS", "SwiftUI"])
        XCTAssertEqual(
            analysis.claims,
            ["A local-first architecture can reduce privacy risk for AI-assisted RSS analysis."]
        )
        XCTAssertEqual(analysis.events, ["OpenAI introduced a new API workflow for desktop developers."])
        XCTAssertEqual(analysis.metrics, ["Setup time reduced by 30%"])
        XCTAssertEqual(analysis.contentType, .announcement)
        XCTAssertEqual(analysis.possibleTopics.count, 2)
        XCTAssertEqual(analysis.importanceScore, 0.82)
        XCTAssertEqual(analysis.modelName, "gpt-fixture")
        XCTAssertEqual(analysis.generatedAt, fixedDate)

        XCTAssertEqual(request.model, "gpt-test")
        XCTAssertEqual(request.temperature, 0.2)
        XCTAssertEqual(request.maxTokens, 1_200)
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertTrue(request.messages[0].content.contains("source: Example Feed"))
        XCTAssertTrue(request.messages[0].content.contains("title: OpenAI improves local-first API workflow"))
        XCTAssertTrue(request.messages[0].content.contains("Return this JSON object"))
    }

    func testAnalyzeArticleRejectsInvalidJSONFixture() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "article-analysis-invalid", withExtension: "json")
        )
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let service = ArticleAnalysisService(
            provider: RecordingAIProvider(response: AIProviderResponse(text: fixture, model: "gpt-fixture"))
        )

        do {
            _ = try await service.analyze(article: article(), sourceTitle: "Example Feed", modelName: "gpt-test")
            XCTFail("Expected invalid JSON to throw")
        } catch let error as ArticleAnalysisValidationError {
            guard case .invalidJSON = error else {
                return XCTFail("Expected invalidJSON, got \(error)")
            }
        }
    }

    func testAnalyzeArticleRejectsEmptyRequiredSummary() async throws {
        let service = ArticleAnalysisService(
            provider: RecordingAIProvider(response: AIProviderResponse(text: validJSON(summary: "   "), model: nil))
        )

        do {
            _ = try await service.analyze(article: article(), sourceTitle: "Example Feed", modelName: "gpt-test")
            XCTFail("Expected empty summary to throw")
        } catch let error as ArticleAnalysisValidationError {
            XCTAssertEqual(error, .emptyField("summary"))
        }
    }

    func testAnalyzeArticleRejectsInvalidContentTypeEnum() async throws {
        let service = ArticleAnalysisService(
            provider: RecordingAIProvider(
                response: AIProviderResponse(text: validJSON(contentType: "unsupported_type"), model: nil)
            )
        )

        do {
            _ = try await service.analyze(article: article(), sourceTitle: "Example Feed", modelName: "gpt-test")
            XCTFail("Expected invalid content type to throw")
        } catch let error as ArticleAnalysisValidationError {
            guard case .invalidJSON = error else {
                return XCTFail("Expected invalidJSON, got \(error)")
            }
        }
    }
}

private func article() -> Article {
    Article(
        id: "article-1",
        feedID: "feed-1",
        title: "OpenAI improves local-first API workflow",
        url: URL(string: "https://example.com/openai-local-first")!,
        publishedAt: fixedDate,
        rssSummary: "OpenAI announced a local-first workflow.",
        content: "The workflow keeps user data local and sends selected text to the configured AI provider.",
        status: .parsed,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
}

private func validJSON(
    summary: String = "Fixture summary",
    contentType: String = "analysis"
) -> String {
    """
    {
      "summary": "\(summary)",
      "key_points": ["Point A"],
      "entities": ["OpenAI"],
      "claims": ["Claim A"],
      "events": ["Event A"],
      "metrics": ["Metric A"],
      "content_type": "\(contentType)",
      "possible_topics": ["Local-first AI workflows"],
      "importance_score": 0.76
    }
    """
}

private actor RecordingAIProvider: AIProvider {
    private let response: AIProviderResponse
    private var requests: [AIProviderRequest] = []

    init(response: AIProviderResponse) {
        self.response = response
    }

    func complete(_ request: AIProviderRequest) async throws -> AIProviderResponse {
        requests.append(request)
        return response
    }

    func allRequests() -> [AIProviderRequest] {
        requests
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
