import XCTest
@testable import RSSRadarCore

final class DomainEnumTests: XCTestCase {
    func testInvalidFeedStatusDoesNotDecode() {
        XCTAssertThrowsError(try decode(FeedStatus.self, from: "\"unknown\""))
    }

    func testInvalidArticleContentSourceDoesNotDecode() {
        XCTAssertThrowsError(try decode(ArticleContentSource.self, from: "\"reader_mode\""))
    }

    func testInvalidArticleStatusDoesNotDecode() {
        XCTAssertThrowsError(try decode(ArticleStatus.self, from: "\"queued\""))
    }

    func testInvalidArticleContentTypeDoesNotDecode() {
        XCTAssertThrowsError(try decode(ArticleContentType.self, from: "\"thread\""))
    }

    func testInvalidTopicStatusDoesNotDecode() {
        XCTAssertThrowsError(try decode(TopicStatus.self, from: "\"deleted\""))
    }

    func testInvalidTopicContributionTypeDoesNotDecode() {
        XCTAssertThrowsError(try decode(TopicContributionType.self, from: "\"noise\""))
    }

    func testInvalidTopicBriefTypeDoesNotDecode() {
        XCTAssertThrowsError(try decode(TopicBriefType.self, from: "\"summary\""))
    }

    func testInvalidAIProviderKindDoesNotDecode() {
        XCTAssertThrowsError(try decode(AIProviderKind.self, from: "\"local_proxy\""))
    }

    func testInvalidScanModeDoesNotDecode() {
        XCTAssertThrowsError(try decode(ScanMode.self, from: "\"daily\""))
    }

    func testInvalidProcessingJobTypeDoesNotDecode() {
        XCTAssertThrowsError(try decode(ProcessingJobType.self, from: "\"unknown\""))
    }

    func testInvalidProcessingJobEntityTypeDoesNotDecode() {
        XCTAssertThrowsError(try decode(ProcessingJobEntityType.self, from: "\"feed_group\""))
    }

    func testInvalidProcessingJobStatusDoesNotDecode() {
        XCTAssertThrowsError(try decode(ProcessingJobStatus.self, from: "\"queued\""))
    }

    func testInvalidOperationLogLevelDoesNotDecode() {
        XCTAssertThrowsError(try decode(OperationLogLevel.self, from: "\"debug\""))
    }
}

private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode(type, from: data)
}
