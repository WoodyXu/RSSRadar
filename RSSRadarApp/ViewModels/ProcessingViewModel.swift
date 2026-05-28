import Foundation
import RSSRadarCore

@MainActor
final class ProcessingViewModel: ObservableObject {
    @Published var jobs: [ProcessingJob] = []
    @Published var logs: [OperationLog] = []
    @Published var hasSavedAPIKey = false
    @Published var isWorking = false
    @Published var statusMessage = "处理队列已就绪。"
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() {
        runSync {
            try refreshSnapshot()
        }
    }

    func runPendingJobs() async {
        await run {
            _ = try await self.environment.processingEngine.recoverInterruptedJobs()
            await self.environment.processingEngine.runPendingJobs()
            try self.refreshSnapshot()
            self.statusMessage = "已运行待处理任务。"
        }
    }

    func retry(job: ProcessingJob) async {
        await run {
            _ = try await self.environment.processingEngine.retry(jobID: job.id)
            await self.environment.processingEngine.runPendingJobs()
            try self.refreshSnapshot()
            self.statusMessage = "已重试\(job.jobType.displayName)。"
        }
    }

    private func refreshSnapshot() throws {
        jobs = try environment.repositories.processingJobs.fetchAll()
        logs = try environment.repositories.operationLogs.fetchRecent(limit: 40)
        hasSavedAPIKey = try environment.repositories.appSettings.fetch().keychainAccountIdentifier != nil
        let failedCount = jobs.filter { $0.status == .failed }.count
        let pendingCount = jobs.filter { $0.status == .pending || $0.status == .running }.count
        statusMessage = jobs.isEmpty
            ? "暂无处理任务。"
            : "\(pendingCount) 个等待中或运行中任务，\(failedCount) 个失败任务。"
    }

    var failedAIJobs: [ProcessingJob] {
        jobs.filter { job in
            job.status == .failed && job.jobType.requiresAIProvider
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = AppViewModelErrorMessage.message(from: error)
        }
        isWorking = false
    }

    private func runSync(_ operation: () throws -> Void) {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            try operation()
        } catch {
            errorMessage = AppViewModelErrorMessage.message(from: error)
        }
        isWorking = false
    }
}

extension ProcessingJobType {
    var requiresAIProvider: Bool {
        switch self {
        case .analyzeArticle, .assignTopics:
            true
        case .fetchFeed, .parseArticle, .generateTopicBrief, .retryFailedJob:
            false
        }
    }
}
