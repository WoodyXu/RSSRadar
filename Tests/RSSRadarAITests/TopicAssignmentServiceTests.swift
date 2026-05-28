import Foundation
import RSSRadarCore
@testable import RSSRadarAI
import XCTest

final class TopicAssignmentServiceTests: XCTestCase {
    func testAssignTopicsParsesExistingAndNewTopicAssignments() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "topic-assignment", withExtension: "json"))
        let fixture = try String(contentsOf: fixtureURL, encoding: .utf8)
        let provider = RecordingTopicAssignmentProvider(response: AIProviderResponse(text: fixture, model: "gpt-topic"))
        let service = TopicAssignmentService(provider: provider)

        let result = try await service.assignTopics(
            analyses: [analysis(articleID: "article-1")],
            existingTopics: [existingTopic()],
            modelName: "gpt-test",
            assignedAt: fixedDate
        )
        let requests = await provider.allRequests()
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(result.modelName, "gpt-topic")
        XCTAssertEqual(result.assignments.count, 2)
        XCTAssertEqual(result.assignments[0].articleID, "article-1")
        XCTAssertEqual(result.assignments[0].topicID, "topic-existing")
        XCTAssertNil(result.assignments[0].newTopic)
        XCTAssertEqual(result.assignments[0].confidence, 0.91)
        XCTAssertEqual(result.assignments[0].contributionType, .newEvent)

        let newAssignment = result.assignments[1]
        XCTAssertEqual(newAssignment.articleID, "article-1")
        XCTAssertNil(newAssignment.topicID)
        XCTAssertEqual(newAssignment.newTopic?.name, "AI coding tools reshape junior developer onboarding")
        XCTAssertEqual(newAssignment.newTopic?.entities, ["AI coding assistants", "junior developers"])
        XCTAssertEqual(newAssignment.newTopic?.importanceScore, 0.78)
        XCTAssertEqual(newAssignment.contributionType, .newOpinion)

        XCTAssertEqual(request.model, "gpt-test")
        XCTAssertEqual(request.temperature, 0.1)
        XCTAssertEqual(request.maxTokens, 8_192)
        XCTAssertEqual(request.responseFormat, .jsonObject)
        XCTAssertTrue(request.messages[0].content.contains("\"article_id\":\"article-1\""))
        XCTAssertTrue(request.messages[0].content.contains("\"topic_id\":\"topic-existing\""))
        XCTAssertTrue(request.messages[0].content.contains("Return exactly this JSON object"))
    }

    func testAssignTopicsAllowsIndustryAssetAndTechnologyDimensionTopics() async throws {
        for topicName in ["AI", "白酒", "新能源车", "比特币", "RAG"] {
            let service = TopicAssignmentService(
                provider: RecordingTopicAssignmentProvider(
                    response: AIProviderResponse(text: topicJSON(name: topicName), model: nil)
                )
            )

            let result = try await service.assignTopics(
                analyses: [analysis(articleID: "article-1")],
                existingTopics: [],
                modelName: "gpt-test"
            )

            XCTAssertEqual(result.assignments.first?.newTopic?.name, topicName)
        }
    }

    func testAssignTopicsRejectsMeaninglessNewTopicName() async throws {
        for topicName in ["新闻", "市场", "公司", "科技", "业务", "news", "market", "company", "technology", "business"] {
            let service = TopicAssignmentService(
                provider: RecordingTopicAssignmentProvider(
                    response: AIProviderResponse(text: topicJSON(name: topicName), model: nil)
                )
            )

            do {
                _ = try await service.assignTopics(
                    analyses: [analysis(articleID: "article-1")],
                    existingTopics: [],
                    modelName: "gpt-test"
                )
                XCTFail("Expected meaningless topic name to throw: \(topicName)")
            } catch let error as TopicAssignmentValidationError {
                XCTAssertEqual(error, .broadTopicName(topicName))
            }
        }
    }

    func testAssignTopicsRejectsUnknownExistingTopicID() async throws {
        let service = TopicAssignmentService(
            provider: RecordingTopicAssignmentProvider(
                response: AIProviderResponse(text: existingTopicJSON(topicID: "missing-topic"), model: nil)
            )
        )

        do {
            _ = try await service.assignTopics(
                analyses: [analysis(articleID: "article-1")],
                existingTopics: [existingTopic()],
                modelName: "gpt-test"
            )
            XCTFail("Expected unknown topic ID to throw")
        } catch let error as TopicAssignmentValidationError {
            XCTAssertEqual(error, .unknownTopicID("missing-topic"))
        }
    }
}

private func analysis(articleID: String) -> ArticleAnalysis {
    ArticleAnalysis(
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
}

private func existingTopic() -> Topic {
    Topic(
        id: "topic-existing",
        name: "Claude Code performance in large Swift codebases",
        description: "Tracks Claude Code behavior on multi-file Swift projects.",
        status: .active,
        importanceScore: 0.7,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
}

private func topicJSON(name: String) -> String {
    """
    {
      "assignments": [
        {
          "article_id": "article-1",
          "topic_id": null,
          "new_topic_name": "\(name)",
          "new_topic_description": "Tracks a specific issue.",
          "confidence": 0.8,
          "reason": "Reason",
          "contribution_type": "new_event"
        }
      ]
    }
    """
}

private func existingTopicJSON(topicID: String) -> String {
    """
    {
      "assignments": [
        {
          "article_id": "article-1",
          "topic_id": "\(topicID)",
          "new_topic_name": null,
          "new_topic_description": null,
          "confidence": 0.8,
          "reason": "Reason",
          "contribution_type": "background"
        }
      ]
    }
    """
}

private actor RecordingTopicAssignmentProvider: AIProvider {
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
