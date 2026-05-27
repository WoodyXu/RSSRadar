// swiftlint:disable file_length
import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence

public struct ProcessingEngineConfiguration: Sendable {
    public var maxConcurrentFeedFetchJobs: Int
    public var maxConcurrentParseArticleJobs: Int
    public var maxConcurrentAnalyzeArticleJobs: Int
    public var maxConcurrentAssignTopicsJobs: Int
    public var maxConcurrentGenerateTopicBriefJobs: Int
    public var retryBackoffSeconds: [TimeInterval]

    public init(
        maxConcurrentFeedFetchJobs: Int = 4,
        maxConcurrentParseArticleJobs: Int = 3,
        maxConcurrentAnalyzeArticleJobs: Int = 2,
        maxConcurrentAssignTopicsJobs: Int = 1,
        maxConcurrentGenerateTopicBriefJobs: Int = 1,
        retryBackoffSeconds: [TimeInterval] = [0, 30]
    ) {
        self.maxConcurrentFeedFetchJobs = max(1, maxConcurrentFeedFetchJobs)
        self.maxConcurrentParseArticleJobs = max(1, maxConcurrentParseArticleJobs)
        self.maxConcurrentAnalyzeArticleJobs = max(1, maxConcurrentAnalyzeArticleJobs)
        self.maxConcurrentAssignTopicsJobs = max(1, maxConcurrentAssignTopicsJobs)
        self.maxConcurrentGenerateTopicBriefJobs = max(1, maxConcurrentGenerateTopicBriefJobs)
        self.retryBackoffSeconds = retryBackoffSeconds.map { max(0, $0) }
    }

    func limit(for jobType: ProcessingJobType) -> Int {
        switch jobType {
        case .fetchFeed:
            maxConcurrentFeedFetchJobs
        case .parseArticle:
            maxConcurrentParseArticleJobs
        case .analyzeArticle:
            maxConcurrentAnalyzeArticleJobs
        case .assignTopics:
            maxConcurrentAssignTopicsJobs
        case .generateTopicBrief:
            maxConcurrentGenerateTopicBriefJobs
        case .retryFailedJob:
            1
        }
    }

    func retryDelay(afterAttempt attemptCount: Int) -> TimeInterval {
        guard attemptCount > 0 else {
            return 0
        }

        let index = attemptCount - 1
        if retryBackoffSeconds.indices.contains(index) {
            return retryBackoffSeconds[index]
        }

        return retryBackoffSeconds.last ?? 0
    }
}

public protocol ProcessingJobExecuting: Sendable {
    func execute(job: ProcessingJob) async throws
}

// swiftlint:disable:next type_body_length
public actor ProcessingEngine {
    private let repositories: RSSRadarRepositories
    private let executor: any ProcessingJobExecuting
    private let configuration: ProcessingEngineConfiguration

    public init(
        repositories: RSSRadarRepositories,
        executor: (any ProcessingJobExecuting)? = nil,
        configuration: ProcessingEngineConfiguration = ProcessingEngineConfiguration()
    ) {
        self.repositories = repositories
        self.executor = executor ?? ProcessingEngineExecutor(repositories: repositories)
        self.configuration = configuration
    }

    @discardableResult
    public func enqueueFeedScan(feedID: String, priority: Int = 0, scheduledAt: Date = Date()) throws -> ProcessingJob {
        let now = Date()
        let job = ProcessingJob(
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: feedID,
            payload: ["feed_id": feedID],
            priority: priority,
            scheduledAt: scheduledAt,
            createdAt: now,
            updatedAt: now
        )
        try repositories.processingJobs.save(job)
        try repositories.operationLogs.save(
            OperationLog(
                level: .info,
                message: "Queued feed scan",
                context: ["job_id": job.id, "feed_id": feedID],
                createdAt: now
            )
        )
        return job
    }

    @discardableResult
    public func enqueueScanAllFeeds(priority: Int = 0, scheduledAt: Date = Date()) throws -> [ProcessingJob] {
        let feeds = try repositories.feeds.fetchAll().filter { $0.status != .paused }
        var jobs: [ProcessingJob] = []
        for feed in feeds {
            jobs.append(try enqueueFeedScan(feedID: feed.id, priority: priority, scheduledAt: scheduledAt))
        }
        return jobs
    }

    @discardableResult
    public func enqueueTopicAssignment(
        articleIDs: [String],
        modelName: String,
        priority: Int = 0,
        scheduledAt: Date = Date()
    ) throws -> [ProcessingJob] {
        let normalizedArticleIDs = articleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedArticleIDs.isEmpty else {
            throw TopicAssignmentUseCaseError.emptyArticleIDs
        }

        let now = Date()
        var jobs: [ProcessingJob] = []
        for batch in normalizedArticleIDs.chunked(size: TopicAssignmentUseCase.defaultBatchSize) {
            let job = ProcessingJob(
                jobType: .assignTopics,
                entityType: .article,
                entityID: batch.first,
                payload: [
                    "article_ids": batch.joined(separator: ","),
                    "model_name": modelName
                ],
                priority: priority,
                scheduledAt: scheduledAt,
                createdAt: now,
                updatedAt: now
            )
            try repositories.processingJobs.save(job)
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Queued topic assignment",
                    context: [
                        "job_id": job.id,
                        "article_count": String(batch.count)
                    ],
                    createdAt: now
                )
            )
            jobs.append(job)
        }

        return jobs
    }

    @discardableResult
    public func enqueueArticleAnalysis(
        articleIDs: [String],
        modelName: String,
        priority: Int = 0,
        scheduledAt: Date = Date()
    ) throws -> [ProcessingJob] {
        let normalizedArticleIDs = articleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedArticleIDs.isEmpty else {
            return []
        }
        guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArticleAnalysisUseCaseError.missingModelName
        }

        let existingArticleIDs = try existingArticleAnalysisJobArticleIDs()
        let articleIDsToQueue = normalizedArticleIDs.filter { !existingArticleIDs.contains($0) }
        guard !articleIDsToQueue.isEmpty else {
            return []
        }

        let now = Date()
        var jobs: [ProcessingJob] = []
        for articleID in articleIDsToQueue {
            let job = ProcessingJob(
                jobType: .analyzeArticle,
                entityType: .article,
                entityID: articleID,
                payload: ["model_name": modelName],
                priority: priority,
                scheduledAt: scheduledAt,
                createdAt: now,
                updatedAt: now
            )
            try repositories.processingJobs.save(job)
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Queued article analysis",
                    context: ["job_id": job.id, "article_id": articleID],
                    createdAt: now
                )
            )
            jobs.append(job)
        }

        return jobs
    }

    @discardableResult
    public func enqueueParsedArticleAnalysis(
        modelName: String,
        maxArticles: Int,
        priority: Int = 0,
        scheduledAt: Date = Date()
    ) throws -> [ProcessingJob] {
        let articles = try repositories.articles.fetch(status: .parsed)
            .prefix(max(1, maxArticles))
            .map(\.id)
        return try enqueueArticleAnalysis(
            articleIDs: Array(articles),
            modelName: modelName,
            priority: priority,
            scheduledAt: scheduledAt
        )
    }

    public func runPendingJobs(now: Date = Date()) async {
        let readyJobs: [ProcessingJob]
        do {
            readyJobs = try repositories.processingJobs.fetchReady(now: now, limit: fetchLimit)
        } catch {
            try? repositories.operationLogs.save(
                OperationLog(
                    level: .error,
                    message: "Failed to load pending jobs",
                    context: ["error": String(describing: error)],
                    createdAt: now
                )
            )
            return
        }

        let selectedJobs = selectRunnableJobs(from: readyJobs)
        await withTaskGroup(of: Void.self) { group in
            for job in selectedJobs {
                group.addTask { [executor, repositories, configuration] in
                    await ProcessingEngine.run(
                        job: job,
                        executor: executor,
                        repositories: repositories,
                        configuration: configuration
                    )
                }
            }
        }
    }

    public func runPendingJobsUntilIdle(maxPasses: Int = 100) async {
        let boundedMaxPasses = max(1, maxPasses)
        for _ in 0..<boundedMaxPasses {
            let readyJobs: [ProcessingJob]
            do {
                readyJobs = try repositories.processingJobs.fetchReady(now: Date(), limit: fetchLimit)
            } catch {
                try? repositories.operationLogs.save(
                    OperationLog(
                        level: .error,
                        message: "Failed to load pending jobs",
                        context: ["error": String(describing: error)],
                        createdAt: Date()
                    )
                )
                return
            }
            guard !readyJobs.isEmpty else {
                return
            }

            await runPendingJobs(now: Date())
        }
    }

    public func retry(jobID: String, scheduledAt: Date = Date()) throws -> ProcessingJob {
        guard var job = try repositories.processingJobs.fetch(id: jobID) else {
            throw ProcessingEngineError.jobNotFound(jobID)
        }
        guard job.status == .failed else {
            throw ProcessingEngineError.jobCannotBeRetried(jobID)
        }

        job.status = .pending
        job.attemptCount = 0
        job.lastErrorMessage = nil
        job.scheduledAt = scheduledAt
        job.startedAt = nil
        job.finishedAt = nil
        job.updatedAt = scheduledAt

        try repositories.processingJobs.save(job)
        try repositories.operationLogs.save(
            OperationLog(
                level: .info,
                message: "Queued failed job for manual retry",
                context: ["job_id": job.id, "job_type": job.jobType.rawValue],
                createdAt: scheduledAt
            )
        )
        return job
    }

    @discardableResult
    public func recoverInterruptedJobs(now: Date = Date()) throws -> Int {
        try ProcessingStartupRecoveryUseCase(repositories: repositories).recover(now: now)
    }

    private var fetchLimit: Int {
        max(
            100,
            ProcessingJobType.allCases.reduce(0) { total, jobType in
                total + configuration.limit(for: jobType)
            }
        )
    }

    private func selectRunnableJobs(from jobs: [ProcessingJob]) -> [ProcessingJob] {
        var selected: [ProcessingJob] = []
        var countsByType: [ProcessingJobType: Int] = [:]

        for job in jobs {
            let count = countsByType[job.jobType, default: 0]
            guard count < configuration.limit(for: job.jobType) else {
                continue
            }

            selected.append(job)
            countsByType[job.jobType] = count + 1
        }

        return selected
    }

    private func existingArticleAnalysisJobArticleIDs() throws -> Set<String> {
        Set(
            try repositories.processingJobs.fetchAll()
                .filter { $0.jobType == .analyzeArticle && $0.entityType == .article }
                .compactMap(\.entityID)
        )
    }

    private static func run(
        job: ProcessingJob,
        executor: any ProcessingJobExecuting,
        repositories: RSSRadarRepositories,
        configuration: ProcessingEngineConfiguration
    ) async {
        let startedAt = Date()
        do {
            try repositories.processingJobs.updateStatus(
                id: job.id,
                status: .running,
                startedAt: startedAt,
                updatedAt: startedAt
            )
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Started processing job",
                    context: ["job_id": job.id, "job_type": job.jobType.rawValue],
                    createdAt: startedAt
                )
            )

            try await executor.execute(job: job)

            let finishedAt = Date()
            try repositories.processingJobs.updateStatus(
                id: job.id,
                status: .completed,
                startedAt: startedAt,
                finishedAt: finishedAt,
                updatedAt: finishedAt
            )
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Completed processing job",
                    context: ["job_id": job.id, "job_type": job.jobType.rawValue],
                    createdAt: finishedAt
                )
            )
        } catch {
            handleFailure(
                job: job,
                error: error,
                startedAt: startedAt,
                repositories: repositories,
                configuration: configuration
            )
        }
    }

    private static func handleFailure(
        job: ProcessingJob,
        error: any Error,
        startedAt: Date,
        repositories: RSSRadarRepositories,
        configuration: ProcessingEngineConfiguration
    ) {
        let finishedAt = Date()
        let nextAttemptCount = job.attemptCount + 1
        let exhaustedAttempts = nextAttemptCount >= job.maxAttempts
        let nextStatus: ProcessingJobStatus = exhaustedAttempts ? .failed : .pending
        let nextScheduledAt = exhaustedAttempts
            ? finishedAt
            : finishedAt.addingTimeInterval(configuration.retryDelay(afterAttempt: nextAttemptCount))

        try? repositories.processingJobs.updateRetryState(
            id: job.id,
            status: nextStatus,
            attemptCount: nextAttemptCount,
            lastErrorMessage: String(describing: error),
            scheduledAt: nextScheduledAt,
            startedAt: startedAt,
            finishedAt: finishedAt,
            updatedAt: finishedAt
        )

        if exhaustedAttempts {
            markArticleFailedIfNeeded(
                job: job,
                error: error,
                repositories: repositories,
                updatedAt: finishedAt
            )
        }

        let logMessage = exhaustedAttempts ? "Processing job failed" : "Processing job scheduled for retry"
        var context = [
            "job_id": job.id,
            "job_type": job.jobType.rawValue,
            "attempt_count": String(nextAttemptCount),
            "max_attempts": String(job.maxAttempts)
        ]
        context.merge(aiFailureDiagnosticContext(from: error)) { current, _ in current }

        try? repositories.operationLogs.save(
            OperationLog(
                level: exhaustedAttempts ? .error : .warning,
                message: logMessage,
                context: context,
                createdAt: finishedAt
            )
        )
    }

    private static func aiFailureDiagnosticContext(from error: any Error) -> [String: String] {
        guard let providerError = error as? AIProviderError else {
            return [:]
        }

        var context = ["ai_error": providerErrorDiagnosticName(providerError)]
        if case let .httpStatus(statusCode) = providerError {
            context["status"] = String(statusCode)
        }
        if let diagnostics = providerError.diagnostics {
            diagnostics.statusCode.map { context["status"] = String($0) }
            diagnostics.finishReason.map { context["finish_reason"] = $0 }
            diagnostics.responsePreview.map { context["response_preview"] = $0 }
        }
        return context
    }

    private static func providerErrorDiagnosticName(_ error: AIProviderError) -> String {
        switch error {
        case .missingAPIKey:
            "missing_api_key"
        case .missingModel:
            "missing_model"
        case .emptyMessages:
            "empty_messages"
        case .invalidBaseURL:
            "invalid_base_url"
        case .httpStatus:
            "http_status"
        case .timedOut:
            "timed_out"
        case .cancelled:
            "cancelled"
        case .network:
            "network"
        case .invalidResponse:
            "invalid_response"
        }
    }

    private static func markArticleFailedIfNeeded(
        job: ProcessingJob,
        error: any Error,
        repositories: RSSRadarRepositories,
        updatedAt: Date
    ) {
        guard job.jobType == .analyzeArticle,
              job.entityType == .article,
              let articleID = job.entityID,
              var article = try? repositories.articles.fetch(id: articleID) else {
            return
        }

        article.status = .failed
        article.errorMessage = String(describing: error)
        article.updatedAt = updatedAt
        try? repositories.articles.save(article)
    }
}

public enum ProcessingEngineError: Error, Equatable, LocalizedError {
    case missingEntityID(String)
    case unsupportedJobType(ProcessingJobType)
    case jobNotFound(String)
    case jobCannotBeRetried(String)
    case invalidPayload(String, String)

    public var errorDescription: String? {
        switch self {
        case let .missingEntityID(jobID):
            "Processing job is missing entity ID: \(jobID)"
        case let .unsupportedJobType(jobType):
            "Processing job type is not executable yet: \(jobType.rawValue)"
        case let .jobNotFound(jobID):
            "Processing job was not found: \(jobID)"
        case let .jobCannotBeRetried(jobID):
            "Processing job is not failed and cannot be manually retried: \(jobID)"
        case let .invalidPayload(jobID, field):
            "Processing job has invalid payload field \(field): \(jobID)"
        }
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        let chunkSize = Swift.max(1, size)
        return stride(from: 0, to: count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, count)])
        }
    }
}
