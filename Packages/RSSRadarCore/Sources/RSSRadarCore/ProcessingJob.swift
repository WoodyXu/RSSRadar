import Foundation

public enum ProcessingJobType: String, Codable, CaseIterable, Sendable {
    case fetchFeed = "fetch_feed"
    case parseArticle = "parse_article"
    case analyzeArticle = "analyze_article"
    case assignTopics = "assign_topics"
    case generateTopicBrief = "generate_topic_brief"
    case retryFailedJob = "retry_failed_job"
}

public enum ProcessingJobEntityType: String, Codable, CaseIterable, Sendable {
    case feed
    case article
    case topic
    case topicBrief = "topic_brief"
    case job
}

public enum ProcessingJobStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case completed
    case failed
}

public struct ProcessingJob: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var jobType: ProcessingJobType
    public var entityType: ProcessingJobEntityType
    public var entityID: String?
    public var payload: [String: String]
    public var status: ProcessingJobStatus
    public var priority: Int
    public var attemptCount: Int
    public var maxAttempts: Int
    public var lastErrorMessage: String?
    public var scheduledAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case jobType = "job_type"
        case entityType = "entity_type"
        case entityID = "entity_id"
        case payload
        case status
        case priority
        case attemptCount = "attempt_count"
        case maxAttempts = "max_attempts"
        case lastErrorMessage = "last_error_message"
        case scheduledAt = "scheduled_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = DomainID.make(),
        jobType: ProcessingJobType,
        entityType: ProcessingJobEntityType,
        entityID: String? = nil,
        payload: [String: String] = [:],
        status: ProcessingJobStatus = .pending,
        priority: Int = 0,
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        lastErrorMessage: String? = nil,
        scheduledAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.jobType = jobType
        self.entityType = entityType
        self.entityID = entityID
        self.payload = payload
        self.status = status
        self.priority = priority
        self.attemptCount = attemptCount
        self.maxAttempts = maxAttempts
        self.lastErrorMessage = lastErrorMessage
        self.scheduledAt = scheduledAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
