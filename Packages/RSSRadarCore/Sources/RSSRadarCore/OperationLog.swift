import Foundation

public enum OperationLogLevel: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
}

public struct OperationLog: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var level: OperationLogLevel
    public var message: String
    public var context: [String: String]
    public var createdAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case level
        case message
        case context
        case createdAt = "created_at"
    }

    public init(
        id: String = DomainID.make(),
        level: OperationLogLevel,
        message: String,
        context: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.level = level
        self.message = message
        self.context = context
        self.createdAt = createdAt
    }
}
