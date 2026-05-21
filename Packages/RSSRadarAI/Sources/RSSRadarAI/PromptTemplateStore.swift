import Foundation

public enum PromptTemplateKind: String, CaseIterable, Sendable {
    case articleAnalysis
    case topicAssignment
    case topicBrief
    case candidateTopicPreview

    var resourceName: String {
        switch self {
        case .articleAnalysis:
            "ArticleAnalysisPrompt"
        case .topicAssignment:
            "TopicAssignmentPrompt"
        case .topicBrief:
            "TopicBriefPrompt"
        case .candidateTopicPreview:
            "CandidateTopicPreviewPrompt"
        }
    }
}

public struct PromptTemplate: Equatable, Sendable {
    public var kind: PromptTemplateKind
    public var content: String

    public init(kind: PromptTemplateKind, content: String) {
        self.kind = kind
        self.content = content
    }

    public func render(variables: [String: String]) throws -> String {
        try PromptInputSanitizer.validate(variables: variables)

        var rendered = content
        for (key, value) in variables {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return rendered
    }
}

public final class PromptTemplateStore: @unchecked Sendable {
    private let bundle: Bundle

    public convenience init() {
        self.init(bundle: .module)
    }

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public func load(_ kind: PromptTemplateKind) throws -> PromptTemplate {
        guard let url = bundle.url(forResource: kind.resourceName, withExtension: "md") else {
            throw PromptTemplateError.missingTemplate(kind.resourceName)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return PromptTemplate(kind: kind, content: content)
        } catch {
            throw PromptTemplateError.unreadableTemplate(kind.resourceName)
        }
    }
}

public enum PromptTemplateError: Error, Equatable, LocalizedError {
    case missingTemplate(String)
    case unreadableTemplate(String)
    case sensitiveInput(String)

    public var errorDescription: String? {
        switch self {
        case let .missingTemplate(name):
            "Prompt template is missing: \(name).md"
        case let .unreadableTemplate(name):
            "Prompt template could not be read: \(name).md"
        case let .sensitiveInput(name):
            "Prompt input contains sensitive material and was rejected: \(name)"
        }
    }
}

private enum PromptInputSanitizer {
    private static let sensitiveMarkers = [
        "api_key",
        "apikey",
        "authorization",
        "bearer ",
        "x-api-key",
        "sk-"
    ]

    static func validate(variables: [String: String]) throws {
        for (key, value) in variables {
            let combined = "\(key)\n\(value)".lowercased()
            if sensitiveMarkers.contains(where: combined.contains) {
                throw PromptTemplateError.sensitiveInput(key)
            }
        }
    }
}
