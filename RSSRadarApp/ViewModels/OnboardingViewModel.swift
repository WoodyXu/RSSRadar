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
    @Published var feedSummary = "No feeds added yet."
    @Published var settingsSummary = "AI provider is not configured."
    @Published var scanSummary = "First scan has not started."
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
                ? "AI provider is not configured."
                : "\(settings.aiProvider.displayName) saved with model \(settings.modelName)."
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
            self.feedSummary = "Added \(feed.title) with status \(feed.status.displayName)."
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
                Imported \(result.importedFeeds.count) feeds, skipped \(result.skippedDuplicates.count), \
                errors \(result.errors.count).
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
            settingsSummary = "\(selectedProvider.displayName) saved with model \(trimmedModel)."
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
                Queued \(jobs.count) feed scans, analyzed \(analyzedArticleIDs.count) articles, \
                assigned \(assignedCount) articles. Candidate topics available: \(self.candidatePreviews.count).
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
            feedSummary = "No feeds added yet."
        } else {
            let activeCount = feeds.filter { $0.status == .active }.count
            feedSummary = "\(feeds.count) feeds saved, \(activeCount) active."
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
            "Model name is required."
        case .emptyAPIKey:
            "API key is required."
        case .invalidBaseURL:
            "Base URL is invalid."
        case .missingSavedAPIKey:
            "Save an AI provider and API key before starting the first scan."
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
            "Custom"
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
            "active"
        case .error:
            "error"
        case .paused:
            "paused"
        case .noArticles:
            "no articles"
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
