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

    public init(
        model: String,
        messages: [AIMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct AIProviderResponse: Equatable, Sendable {
    public var text: String
    public var model: String?

    public init(text: String, model: String? = nil) {
        self.text = text
        self.model = model
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
        timeoutSeconds: TimeInterval = 60
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
    case invalidResponse(String)

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
        case let .invalidResponse(message):
            "AI Provider returned an invalid response: \(message)"
        }
    }
}
