import Foundation

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case anthropic
    case custom
}

public enum ScanMode: String, Codable, CaseIterable, Sendable {
    case manual
    case onLaunch = "on_launch"
    case interval
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiProvider: AIProviderKind
    public var baseURL: URL
    public var modelName: String
    public var databasePath: String?
    public var keychainAccountIdentifier: String?
    public var scanMode: ScanMode
    public var scanIntervalHours: Int
    public var maxArticlesPerScan: Int
    public var maxArticlesForNewFeed: Int
    public var maxArticlesPerTopicBatch: Int
    public var aiRequestTimeoutSeconds: Int

    public enum CodingKeys: String, CodingKey {
        case aiProvider = "ai_provider"
        case baseURL = "base_url"
        case modelName = "model_name"
        case databasePath = "database_path"
        case keychainAccountIdentifier = "keychain_account_identifier"
        case scanMode = "scan_mode"
        case scanIntervalHours = "scan_interval_hours"
        case maxArticlesPerScan = "max_articles_per_scan"
        case maxArticlesForNewFeed = "max_articles_for_new_feed"
        case maxArticlesPerTopicBatch = "max_articles_per_topic_batch"
        case aiRequestTimeoutSeconds = "ai_request_timeout_seconds"
    }

    public init(
        aiProvider: AIProviderKind = .openAICompatible,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        modelName: String = "",
        databasePath: String? = nil,
        keychainAccountIdentifier: String? = nil,
        scanMode: ScanMode = .manual,
        scanIntervalHours: Int = 6,
        maxArticlesPerScan: Int = 100,
        maxArticlesForNewFeed: Int = 20,
        maxArticlesPerTopicBatch: Int = 20,
        aiRequestTimeoutSeconds: Int = 120
    ) {
        self.aiProvider = aiProvider
        self.baseURL = baseURL
        self.modelName = modelName
        self.databasePath = databasePath
        self.keychainAccountIdentifier = keychainAccountIdentifier
        self.scanMode = scanMode
        self.scanIntervalHours = scanIntervalHours
        self.maxArticlesPerScan = maxArticlesPerScan
        self.maxArticlesForNewFeed = maxArticlesForNewFeed
        self.maxArticlesPerTopicBatch = maxArticlesPerTopicBatch
        self.aiRequestTimeoutSeconds = aiRequestTimeoutSeconds
    }
}
