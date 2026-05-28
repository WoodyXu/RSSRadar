import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var feedURLString = ""
    @Published var selectedProvider: AIProviderKind = .openAICompatible {
        didSet {
            if selectedProvider != oldValue {
                baseURLString = Self.defaultBaseURL(for: selectedProvider).absoluteString
            }
        }
    }
    @Published var baseURLString = AIProviderKind.openAICompatible.defaultBaseURL.absoluteString
    @Published var modelName = ""
    @Published var apiKey = ""
    @Published var maxArticlesPerScan = 100
    @Published var isWorking = false
    @Published var feedSummary = "还没有添加内容源。"
    @Published var settingsSummary = "尚未配置 AI 服务商。"
    @Published var scanSummary = "首次扫描尚未开始。"
    @Published var candidatePreviews: [CandidateTopicPreview] = []
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() {
        do {
            let settings = try environment.repositories.appSettings.fetch()
            selectedProvider = settings.aiProvider
            baseURLString = settings.baseURL.absoluteString
            modelName = settings.modelName
            maxArticlesPerScan = settings.maxArticlesPerScan
            settingsSummary = settings.keychainAccountIdentifier == nil
                ? "尚未配置 AI 服务商。"
                : "已保存 \(settings.aiProvider.displayName)，Model：\(settings.modelName)。"
            try refreshFeedSummary()
            try refreshCandidates()
        } catch {
            errorMessage = Self.message(from: error)
        }
    }

    func addManualFeed() async {
        await run { [self] in
            let feed = try await self.environment.manualFeedAddUseCase.addFeed(urlString: self.feedURLString)
            self.feedURLString = ""
            self.feedSummary = "已添加 \(feed.title)，状态：\(feed.status.displayName)。"
        }
    }

    func importOPML(from url: URL) {
        runSync {
            let shouldStopAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let result = try environment.opmlImportUseCase.importOPML(data: data)
            feedSummary = """
                已导入 \(result.importedFeeds.count) 个内容源，跳过 \(result.skippedDuplicates.count) 个重复源，\
                错误 \(result.errors.count) 个。
                """
        }
    }

    func saveAISettings() {
        runSync {
            let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModel.isEmpty else {
                throw OnboardingError.emptyModel
            }
            guard !trimmedKey.isEmpty else {
                throw OnboardingError.emptyAPIKey
            }
            guard let baseURL = URL(string: baseURLString), baseURL.scheme?.isEmpty == false else {
                throw OnboardingError.invalidBaseURL
            }

            var settings = try environment.repositories.appSettings.fetch()
            let accountIdentifier = settings.keychainAccountIdentifier ?? KeychainAPIKeyStore.makeAccountIdentifier()
            try environment.keychainStore.saveAPIKey(trimmedKey, accountIdentifier: accountIdentifier)

            settings.aiProvider = selectedProvider
            settings.baseURL = baseURL
            settings.modelName = trimmedModel
            settings.databasePath = AppEnvironment.defaultDatabasePath()
            settings.keychainAccountIdentifier = accountIdentifier
            settings.maxArticlesPerScan = max(1, maxArticlesPerScan)
            try environment.repositories.appSettings.save(settings)

            apiKey = ""
            settingsSummary = "已保存 \(selectedProvider.displayName)，Model：\(trimmedModel)。"
        }
    }

    func startFirstScan() async {
        await run { [self] in
            _ = try await self.environment.processingEngine.recoverInterruptedJobs()
            let jobs = try await self.environment.processingEngine.enqueueScanAllFeeds()
            await self.environment.processingEngine.runPendingJobs()

            let settings = try self.environment.repositories.appSettings.fetch()
            let analyzedArticleIDs = try await self.analyzeParsedArticles(settings: settings)
            let assignedCount = try await self.assignTopics(articleIDs: analyzedArticleIDs, settings: settings)

            try self.refreshCandidates()
            self.scanSummary = """
                已排队 \(jobs.count) 个内容源扫描，分析 \(analyzedArticleIDs.count) 篇文章，\
                完成 \(assignedCount) 篇文章的主题归类。可查看 \(self.candidatePreviews.count) 个待确认主题。
                """
        }
    }

    private func analyzeParsedArticles(settings: AppSettings) async throws -> [String] {
        let articles = try environment.repositories.articles.fetch(status: .parsed)
            .prefix(max(1, settings.maxArticlesPerScan))
        guard !articles.isEmpty else {
            return []
        }

        let provider = try makeProvider(settings: settings)
        let analyzer = ArticleAnalysisService(provider: provider)
        let useCase = ArticleAnalysisUseCase(repositories: environment.repositories, analyzer: analyzer)
        var analyzedArticleIDs: [String] = []

        for article in articles {
            _ = try await useCase.analyzeArticle(id: article.id, modelName: settings.modelName)
            analyzedArticleIDs.append(article.id)
        }

        return analyzedArticleIDs
    }

    private func assignTopics(articleIDs: [String], settings: AppSettings) async throws -> Int {
        guard !articleIDs.isEmpty else {
            return 0
        }

        let provider = try makeProvider(settings: settings)
        let assigner = TopicAssignmentService(provider: provider)
        let batchSize = max(1, settings.maxArticlesPerTopicBatch)
        let useCase = TopicAssignmentUseCase(
            repositories: environment.repositories,
            topicAssigner: assigner,
            batchSize: batchSize
        )
        var assignedCount = 0

        for batch in articleIDs.chunked(size: batchSize) {
            _ = try await useCase.assignTopics(articleIDs: batch, modelName: settings.modelName)
            assignedCount += batch.count
        }

        return assignedCount
    }

    private func makeProvider(settings: AppSettings) throws -> URLSessionAIProvider {
        guard let accountIdentifier = settings.keychainAccountIdentifier else {
            throw OnboardingError.missingSavedAPIKey
        }
        guard let apiKey = try environment.keychainStore.readAPIKey(accountIdentifier: accountIdentifier) else {
            throw OnboardingError.missingSavedAPIKey
        }

        return URLSessionAIProvider(
            kind: settings.aiProvider,
            baseURL: settings.baseURL,
            apiKey: apiKey,
            timeoutSeconds: TimeInterval(settings.aiRequestTimeoutSeconds)
        )
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        guard !isWorking else {
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            try await operation()
            try refreshFeedSummary()
        } catch {
            errorMessage = Self.message(from: error)
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
            try refreshFeedSummary()
            try refreshCandidates()
        } catch {
            errorMessage = Self.message(from: error)
        }
        isWorking = false
    }

    private func refreshFeedSummary() throws {
        let feeds = try environment.repositories.feeds.fetchAll()
        if feeds.isEmpty {
            feedSummary = "还没有添加内容源。"
        } else {
            let activeCount = feeds.filter { $0.status == .active }.count
            feedSummary = "已保存 \(feeds.count) 个内容源，\(activeCount) 个正常。"
        }
    }

    private func refreshCandidates() throws {
        candidatePreviews = try environment.candidateTopicManagementUseCase.listCandidates()
    }

    private static func defaultBaseURL(for provider: AIProviderKind) -> URL {
        provider.defaultBaseURL
    }

    private static func message(from error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private enum OnboardingError: Error, LocalizedError {
    case emptyModel
    case emptyAPIKey
    case invalidBaseURL
    case missingSavedAPIKey

    var errorDescription: String? {
        switch self {
        case .emptyModel:
            "请填写 Model。"
        case .emptyAPIKey:
            "请填写 API Key。"
        case .invalidBaseURL:
            "Base URL 无效。"
        case .missingSavedAPIKey:
            "请先保存 AI Provider 和 API Key，再开始首次扫描。"
        }
    }
}

extension AIProviderKind: Identifiable {
    public var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openAICompatible:
            "OpenAI-compatible"
        case .anthropic:
            "Anthropic"
        case .custom:
            "自定义"
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .openAICompatible, .custom:
            URL(string: "https://api.openai.com/v1")!
        case .anthropic:
            URL(string: "https://api.anthropic.com")!
        }
    }
}

private extension FeedStatus {
    var displayName: String {
        switch self {
        case .active:
            "正常"
        case .error:
            "异常"
        case .paused:
            "已暂停"
        case .noArticles:
            "暂无文章"
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
