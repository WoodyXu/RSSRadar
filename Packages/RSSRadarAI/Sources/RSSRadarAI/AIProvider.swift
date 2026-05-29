import Foundation
import RSSRadarCore

public enum AIMessageRole: String, Codable, Equatable, Sendable {
    case system
    case user
    case assistant
}
public struct AIMessage: Codable, Equatable, Sendable {
    public var role: AIMessageRole
    public var content: String

    public init(role: AIMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIProviderRequest: Equatable, Sendable {
    public var model: String
    public var messages: [AIMessage]
    public var temperature: Double?
    public var maxTokens: Int?
    public var responseFormat: AIResponseFormat?

    public init(
        model: String,
        messages: [AIMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        responseFormat: AIResponseFormat? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.responseFormat = responseFormat
    }
}

public enum AIResponseFormat: String, Codable, Equatable, Sendable {
    case jsonObject = "json_object"
}

public struct AIProviderResponse: Equatable, Sendable {
    public var text: String
    public var model: String?
    public var finishReason: String?

    public init(text: String, model: String? = nil, finishReason: String? = nil) {
        self.text = text
        self.model = model
        self.finishReason = finishReason
    }
}

public struct AIProviderResponseDiagnostics: Equatable, Sendable {
    public var statusCode: Int?
    public var finishReason: String?
    public var responsePreview: String?

    public init(statusCode: Int? = nil, finishReason: String? = nil, responsePreview: String? = nil) {
        self.statusCode = statusCode
        self.finishReason = finishReason
        self.responsePreview = responsePreview
    }
}

public struct AIProviderConfiguration: Equatable, Sendable {
    public var kind: AIProviderKind
    public var baseURL: URL
    public var apiKey: String
    public var timeoutSeconds: TimeInterval

    public init(
        kind: AIProviderKind,
        baseURL: URL? = nil,
        apiKey: String,
        timeoutSeconds: TimeInterval = 120
    ) {
        self.kind = kind
        self.baseURL = baseURL ?? Self.defaultBaseURL(for: kind)
        self.apiKey = apiKey
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    public static func defaultBaseURL(for kind: AIProviderKind) -> URL {
        switch kind {
        case .openAICompatible, .custom:
            URL(string: "https://api.openai.com/v1")!
        case .anthropic:
            URL(string: "https://api.anthropic.com")!
        }
    }
}

public protocol AIProvider: Sendable {
    func complete(_ request: AIProviderRequest) async throws -> AIProviderResponse
}

public enum AIProviderError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case missingModel
    case emptyMessages
    case invalidBaseURL(String)
    case httpStatus(Int)
    case timedOut
    case cancelled
    case network(String)
    case invalidResponse(String, diagnostics: AIProviderResponseDiagnostics? = nil)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "AI API Key is not configured."
        case .missingModel:
            "AI model name is not configured."
        case .emptyMessages:
            "AI request has no messages."
        case let .invalidBaseURL(value):
            "AI Provider base URL is invalid: \(value)"
        case let .httpStatus(statusCode):
            "AI Provider request failed with HTTP status \(statusCode)."
        case .timedOut:
            "AI Provider request timed out."
        case .cancelled:
            "AI Provider request was cancelled."
        case let .network(message):
            "AI Provider network request failed: \(message)"
        case let .invalidResponse(message, diagnostics):
            if let diagnostics {
                [
                    "AI Provider returned an invalid response: \(message)",
                    diagnostics.statusCode.map { "status=\($0)" },
                    diagnostics.finishReason.map { "finish_reason=\($0)" },
                    diagnostics.responsePreview.map { "response_preview=\($0)" }
                ]
                    .compactMap { $0 }
                    .joined(separator: "; ")
            } else {
                "AI Provider returned an invalid response: \(message)"
            }
        }
    }

    public var diagnostics: AIProviderResponseDiagnostics? {
        switch self {
        case let .invalidResponse(_, diagnostics):
            diagnostics
        default:
            nil
        }
    }
}
