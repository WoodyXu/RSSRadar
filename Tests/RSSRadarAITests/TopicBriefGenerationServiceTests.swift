import Foundation
import RSSRadarCore
@testable import RSSRadarAI
import XCTest

final class TopicBriefGenerationServiceTests: XCTestCase {
    func testGenerateFullBriefParsesFixtureAndBuildsSourceEvidence() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "topic-brief", withExtension: "json"))
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let provider = RecordingTopicBriefProvider(response: AIProviderResponse(text: fixture, model: "gpt-brief"))
        let service = TopicBriefGenerationService(provider: provider)

        let brief = try await service.generateBrief(
            topic: topic(status: .active),
            relatedArticles: [sourceArticle(articleID: "article-1")],
            briefType: .full,
            modelName: "gpt-test",
            generatedAt: fixedDate
        )
        let requests = await provider.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(brief.briefType, .full)
        XCTAssertEqual(brief.currentTakeaway, "Claude Code 在大型 Swift 代码库中的采用正在从试验转向团队级流程。")
        XCTAssertEqual(brief.modelName, "gpt-brief")
        XCTAssertEqual(brief.generatedAt, fixedDate)
        XCTAssertEqual(brief.latestChanges.first?.text, "团队开始把多文件编辑和新人 onboarding 纳入 Claude Code 的正式评估。")
        XCTAssertEqual(brief.timeline.first?.title, "团队扩大 Claude Code 使用范围")
        XCTAssertEqual(brief.viewpoints.first?.summary, "支持者认为 Claude Code 能缩短熟悉大型代码库的时间，但仍需要人工 review 控制风险。")
        XCTAssertEqual(brief.evidence.first?.sourceArticleID, "article-1")
        XCTAssertEqual(brief.evidence.first?.sourceArticleTitle, "Claude Code adoption update")
        XCTAssertEqual(brief.evidence.first?.sourceName, "Example Feed")
        XCTAssertEqual(brief.relatedArticleIDs, ["article-1"])
        XCTAssertEqual(request.model, "gpt-test")
        XCTAssertEqual(request.maxTokens, 2_400)
        XCTAssertTrue(request.messages[0].content.contains("\"topic_id\":\"topic-1\""))
        XCTAssertTrue(request.messages[0].content.contains("\"article_id\":\"article-1\""))
        XCTAssertTrue(request.messages[0].content.contains("Generate a full Chinese intelligence brief"))
    }

    func testGeneratePreviewUsesCandidatePromptAndShorterTokenLimit() async throws {
        let response = """
        {
          "current_takeaway": "候选主题足够具体，值得观察。",
          "latest_changes": ["出现了新的支持文章。"],
          "evidence": [{"text": "文章讨论 onboarding 影响。", "article_id": "article-1"}],
          "questions_to_watch": ["是否持续出现新证据？"],
          "related_article_ids": ["article-1"]
        }
        """
        let provider = RecordingTopicBriefProvider(response: AIProviderResponse(text: response, model: nil))
        let service = TopicBriefGenerationService(provider: provider)

        let brief = try await service.generateBrief(
            topic: topic(status: .candidate),
            relatedArticles: [sourceArticle(articleID: "article-1")],
            briefType: .preview,
            modelName: "gpt-test",
            generatedAt: fixedDate
        )
        let requests = await provider.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(brief.briefType, .preview)
        XCTAssertEqual(brief.timeline, [])
        XCTAssertEqual(brief.viewpoints, [])
        XCTAssertEqual(brief.modelName, "gpt-test")
        XCTAssertEqual(request.maxTokens, 1_200)
        XCTAssertTrue(request.messages[0].content.contains("candidate topic preview writer"))
    }

    func testGenerateBriefRejectsUnknownEvidenceArticleID() async throws {
        let provider = RecordingTopicBriefProvider(
            response: AIProviderResponse(
                text: """
                {
                  "current_takeaway": "结论",
                  "latest_changes": [],
                  "evidence": [{"text": "证据", "article_id": "missing"}],
                  "questions_to_watch": [],
                  "related_article_ids": []
                }
                """,
                model: nil
            )
        )
        let service = TopicBriefGenerationService(provider: provider)

        do {
            _ = try await service.generateBrief(
                topic: topic(status: .candidate),
                relatedArticles: [sourceArticle(articleID: "article-1")],
                briefType: .preview,
                modelName: "gpt-test"
            )
            XCTFail("Expected unknown article ID to throw")
        } catch let error as TopicBriefValidationError {
            XCTAssertEqual(error, .unknownArticleID("missing"))
        }
    }
}

private func topic(status: TopicStatus) -> Topic {
    Topic(
        id: "topic-1",
        name: "Claude Code performance in large Swift codebases",
        description: "Tracks Claude Code behavior on large Swift projects.",
        status: status,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
}

private func sourceArticle(articleID: String) -> TopicBriefSourceArticle {
    let article = Article(
        id: articleID,
        feedID: "feed-1",
        title: "Claude Code adoption update",
        url: URL(string: "https://example.com/article-1")!,
        publishedAt: fixedDate,
        status: .assigned,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let analysis = ArticleAnalysis(
        articleID: articleID,
        summary: "Claude Code adoption improved in a large Swift codebase.",
        keyPoints: ["Teams adopted AI coding tools for multi-file edits."],
        entities: ["Claude Code", "Swift"],
        claims: ["AI coding tools can speed onboarding."],
        events: ["A team expanded Claude Code usage."],
        metrics: ["30% faster setup"],
        contentType: .analysis,
        possibleTopics: ["Claude Code in large Swift codebases"],
        importanceScore: 0.82,
        modelName: "gpt-test",
        generatedAt: fixedDate
    )
    return TopicBriefSourceArticle(
        article: article,
        analysis: analysis,
        feedTitle: "Example Feed",
        contributionType: .newData
    )
}

private actor RecordingTopicBriefProvider: AIProvider {
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
