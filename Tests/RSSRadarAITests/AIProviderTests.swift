import Foundation
import RSSRadarCore
@testable import RSSRadarAI
import XCTest

final class AIProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFakeAIProviderUsesProviderAbstraction() async throws {
        let provider = FakeAIProvider(response: AIProviderResponse(text: "fake result", model: "fake-model"))
        let response = try await provider.complete(sampleRequest)

        XCTAssertEqual(response.text, "fake result")
        XCTAssertEqual(response.model, "fake-model")
        let requests = await provider.allRequests()
        XCTAssertEqual(requests, [sampleRequest])
    }

    func testDefaultBaseURLsMatchProviderKinds() {
        XCTAssertEqual(
            AIProviderConfiguration.defaultBaseURL(for: .openAICompatible).absoluteString,
            "https://api.openai.com/v1"
        )
        XCTAssertEqual(
            AIProviderConfiguration.defaultBaseURL(for: .anthropic).absoluteString,
            "https://api.anthropic.com"
        )
    }

    func testOpenAICompatibleProviderBuildsChatCompletionsRequest() async throws {
        MockURLProtocol.responseData = Data("""
        {"model":"gpt-test","choices":[{"message":{"content":"openai text"}}]}
        """.utf8)
        MockURLProtocol.statusCode = 200

        let provider = URLSessionAIProvider(
            kind: .openAICompatible,
            apiKey: "test-key",
            timeoutSeconds: 12,
            session: makeMockSession()
        )
        let response = try await provider.complete(sampleRequest)
        let capturedRequest = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try decodedJSONBody(from: capturedRequest)

        XCTAssertEqual(response, AIProviderResponse(text: "openai text", model: "gpt-test"))
        XCTAssertEqual(capturedRequest.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(capturedRequest.httpMethod, "POST")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest.timeoutInterval, 12)
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [
            ["role": "system", "content": "You are concise."],
            ["role": "user", "content": "Summarize this."]
        ])
    }

    func testCustomProviderUsesCustomBaseURLWithChatCompletionsFormat() async throws {
        MockURLProtocol.responseData = Data("""
        {"choices":[{"message":{"content":"custom text"}}]}
        """.utf8)
        MockURLProtocol.statusCode = 200

        let provider = URLSessionAIProvider(
            kind: .custom,
            baseURL: try XCTUnwrap(URL(string: "https://ai.example.com/custom/v1/")),
            apiKey: "custom-key",
            session: makeMockSession()
        )
        let response = try await provider.complete(sampleRequest)
        let capturedRequest = try XCTUnwrap(MockURLProtocol.capturedRequests.first)

        XCTAssertEqual(response.text, "custom text")
        XCTAssertEqual(capturedRequest.url?.absoluteString, "https://ai.example.com/custom/v1/chat/completions")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
    }

    func testAnthropicProviderBuildsMessagesRequest() async throws {
        MockURLProtocol.responseData = Data("""
        {"model":"claude-test","content":[{"type":"text","text":"anthropic text"}]}
        """.utf8)
        MockURLProtocol.statusCode = 200

        let provider = URLSessionAIProvider(
            kind: .anthropic,
            apiKey: "anthropic-key",
            session: makeMockSession()
        )
        let response = try await provider.complete(sampleRequest)
        let capturedRequest = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try decodedJSONBody(from: capturedRequest)

        XCTAssertEqual(response, AIProviderResponse(text: "anthropic text", model: "claude-test"))
        XCTAssertEqual(capturedRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "x-api-key"), "anthropic-key")
        XCTAssertEqual(capturedRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["system"] as? String, "You are concise.")
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "Summarize this."]])
    }

    func testHTTPStatusMapsToUserUnderstandableError() async throws {
        MockURLProtocol.statusCode = 429
        MockURLProtocol.responseData = Data()
        let provider = URLSessionAIProvider(
            kind: .openAICompatible,
            apiKey: "test-key",
            session: makeMockSession()
        )

        do {
            _ = try await provider.complete(sampleRequest)
            XCTFail("Expected HTTP status error")
        } catch AIProviderError.httpStatus(429) {
            XCTAssertEqual(
                AIProviderError.httpStatus(429).errorDescription,
                "AI Provider request failed with HTTP status 429."
            )
        }
    }

    func testTimedOutAndCancelledErrorsAreMapped() async {
        await XCTAssertThrowsAIError(.timedOut, urlError: URLError(.timedOut))
        await XCTAssertThrowsAIError(.cancelled, urlError: URLError(.cancelled))
    }

    func testValidationErrorsDoNotPerformNetworkRequest() async {
        let provider = URLSessionAIProvider(kind: .openAICompatible, apiKey: "", session: makeMockSession())

        do {
            _ = try await provider.complete(sampleRequest)
            XCTFail("Expected missing API Key error")
        } catch AIProviderError.missingAPIKey {
            XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private let sampleRequest = AIProviderRequest(
    model: "test-model",
    messages: [
        AIMessage(role: .system, content: "You are concise."),
        AIMessage(role: .user, content: "Summarize this.")
    ],
    temperature: 0.2,
    maxTokens: 256
)

private actor FakeAIProvider: AIProvider {
    private let response: AIProviderResponse
    private(set) var requests: [AIProviderRequest] = []

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

private extension AIProviderTests {
    func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func decodedJSONBody(from request: URLRequest) throws -> [String: Any] {
        let body = try requestBodyData(from: request)
        let json = try JSONSerialization.jsonObject(with: body)
        return try XCTUnwrap(json as? [String: Any])
    }

    func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? AIProviderError.invalidResponse("Unable to read request body.")
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    func XCTAssertThrowsAIError(
        _ expectedError: AIProviderError,
        urlError: URLError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        MockURLProtocol.error = urlError
        let provider = URLSessionAIProvider(kind: .openAICompatible, apiKey: "test-key", session: makeMockSession())

        do {
            _ = try await provider.complete(sampleRequest)
            XCTFail("Expected \(expectedError)", file: file, line: line)
        } catch let error as AIProviderError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
        MockURLProtocol.reset()
    }
}

private final class MockURLProtocol: URLProtocol {
    static var statusCode = 200
    static var responseData = Data()
    static var error: Error?
    private(set) static var capturedRequests: [URLRequest] = []

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.capturedRequests.append(request)
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        statusCode = 200
        responseData = Data()
        error = nil
        capturedRequests = []
    }
}
