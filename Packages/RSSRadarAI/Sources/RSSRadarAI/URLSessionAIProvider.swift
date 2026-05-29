import Foundation
import RSSRadarCore

public final class URLSessionAIProvider: AIProvider, @unchecked Sendable {
    private let configuration: AIProviderConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: AIProviderConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public convenience init(
        kind: AIProviderKind,
        baseURL: URL? = nil,
        apiKey: String,
        timeoutSeconds: TimeInterval = 120,
        session: URLSession = .shared
    ) {
        self.init(
            configuration: AIProviderConfiguration(
                kind: kind,
                baseURL: baseURL,
                apiKey: apiKey,
                timeoutSeconds: timeoutSeconds
            ),
            session: session
        )
    }

    public func complete(_ request: AIProviderRequest) async throws -> AIProviderResponse {
        try validate(request)

        let urlRequest: URLRequest
        switch configuration.kind {
        case .openAICompatible, .custom:
            urlRequest = try makeOpenAICompatibleRequest(request)
        case .anthropic:
            urlRequest = try makeAnthropicRequest(request)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            try validateHTTPResponse(response)
            return try decodeResponse(data, for: configuration.kind)
        } catch let error as AIProviderError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw AIProviderError.timedOut
        } catch let error as URLError where error.code == .cancelled {
            throw AIProviderError.cancelled
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch {
            throw AIProviderError.network(String(describing: error))
        }
    }

    private func validate(_ request: AIProviderRequest) throws {
        guard configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AIProviderError.missingAPIKey
        }
        guard request.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AIProviderError.missingModel
        }
        guard request.messages.isEmpty == false else {
            throw AIProviderError.emptyMessages
        }
    }

    private func makeOpenAICompatibleRequest(_ request: AIProviderRequest) throws -> URLRequest {
        let endpoint = try endpointURL(path: "chat/completions")
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: configuration.timeoutSeconds)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(OpenAICompatibleRequestBody(from: request))
        return urlRequest
    }

    private func makeAnthropicRequest(_ request: AIProviderRequest) throws -> URLRequest {
        let endpoint = try endpointURL(path: "v1/messages")
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: configuration.timeoutSeconds)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try encoder.encode(AnthropicRequestBody(from: request))
        return urlRequest
    }

    private func endpointURL(path: String) throws -> URL {
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(path)") else {
            throw AIProviderError.invalidBaseURL(configuration.baseURL.absoluteString)
        }
        return url
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse("Missing HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIProviderError.httpStatus(httpResponse.statusCode)
        }
    }

    private func decodeResponse(_ data: Data, for kind: AIProviderKind) throws -> AIProviderResponse {
        switch kind {
        case .openAICompatible, .custom:
            let response = try decoder.decode(OpenAICompatibleResponseBody.self, from: data)
            let choice = response.choices.first
            let text = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, text.isEmpty == false else {
                throw AIProviderError.invalidResponse(
                    "Missing assistant message content.",
                    diagnostics: AIProviderResponseDiagnostics(
                        statusCode: 200,
                        finishReason: choice?.finishReason,
                        responsePreview: Self.responsePreview(from: data)
                    )
                )
            }
            return AIProviderResponse(text: text, model: response.model, finishReason: choice?.finishReason)
        case .anthropic:
            let response = try decoder.decode(AnthropicResponseBody.self, from: data)
            let text = response.content
                .filter { $0.type == "text" }
                .map(\.text)
                .joined(separator: "\n")
            guard text.isEmpty == false else {
                throw AIProviderError.invalidResponse("Missing text content.")
            }
            return AIProviderResponse(text: text, model: response.model)
        }
    }

    private static func responsePreview(from data: Data, limit: Int = 500) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }
        return String(normalized.prefix(limit))
    }
}
private struct OpenAICompatibleRequestBody: Encodable {
    var model: String
    var messages: [OpenAICompatibleMessage]
    var temperature: Double?
    var maxTokens: Int?
    var responseFormat: OpenAICompatibleResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }

    init(from request: AIProviderRequest) {
        model = request.model
        messages = request.messages.map(OpenAICompatibleMessage.init)
        temperature = request.temperature
        maxTokens = request.maxTokens
        responseFormat = request.responseFormat.map(OpenAICompatibleResponseFormat.init)
    }
}

private struct OpenAICompatibleResponseFormat: Encodable {
    var type: String

    init(_ format: AIResponseFormat) {
        switch format {
        case .jsonObject:
            type = "json_object"
        }
    }
}

private struct OpenAICompatibleMessage: Codable {
    var role: String
    var content: String

    init(_ message: AIMessage) {
        role = message.role.rawValue
        content = message.content
    }
}

private struct OpenAICompatibleResponseBody: Decodable {
    var model: String?
    var choices: [OpenAICompatibleChoice]
}

private struct OpenAICompatibleChoice: Decodable {
    var message: OpenAICompatibleResponseMessage
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenAICompatibleResponseMessage: Decodable {
    var content: String?
}

private struct AnthropicRequestBody: Encodable {
    var model: String
    var system: String?
    var messages: [AnthropicMessage]
    var maxTokens: Int
    var temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case temperature
    }

    init(from request: AIProviderRequest) {
        model = request.model
        system = request.messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        if system?.isEmpty == true {
            system = nil
        }
        messages = request.messages
            .filter { $0.role != .system }
            .map(AnthropicMessage.init)
        maxTokens = request.maxTokens ?? 1_024
        temperature = request.temperature
    }
}

private struct AnthropicMessage: Codable {
    var role: String
    var content: String

    init(_ message: AIMessage) {
        role = message.role == .assistant ? "assistant" : "user"
        content = message.content
    }
}

private struct AnthropicResponseBody: Decodable {
    var model: String?
    var content: [Content]

    struct Content: Decodable {
        var type: String
        var text: String
    }
}
