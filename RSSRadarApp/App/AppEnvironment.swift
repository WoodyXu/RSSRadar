import Foundation
import RSSRadarAI
import RSSRadarPersistence
import RSSRadarProcessing

final class AppEnvironment {
    let database: RSSRadarDatabase
    let repositories: RSSRadarRepositories
    let keychainStore: KeychainAPIKeyStore
    let manualFeedAddUseCase: ManualFeedAddUseCase
    let opmlImportUseCase: OPMLImportUseCase
    let processingEngine: ProcessingEngine
    let candidateTopicManagementUseCase: CandidateTopicManagementUseCase

    init(databasePath: String = AppEnvironment.defaultDatabasePath()) throws {
        database = try RSSRadarDatabase(path: databasePath)
        try database.migrate()

        repositories = RSSRadarRepositories(database: database)
        keychainStore = KeychainAPIKeyStore()
        _ = try ProcessingStartupRecoveryUseCase(repositories: repositories).recover()
        manualFeedAddUseCase = ManualFeedAddUseCase(repositories: repositories)
        opmlImportUseCase = OPMLImportUseCase(repositories: repositories)
        let repositories = repositories
        let keychainStore = keychainStore
        processingEngine = ProcessingEngine(
            repositories: repositories,
            executor: ProcessingEngineExecutor(
                repositories: repositories,
                aiProviderFactory: {
                    let settings = try repositories.appSettings.fetch()
                    guard let accountIdentifier = settings.keychainAccountIdentifier else {
                        throw AIProviderError.missingAPIKey
                    }
                    guard let apiKey = try keychainStore.readAPIKey(accountIdentifier: accountIdentifier) else {
                        throw AIProviderError.missingAPIKey
                    }
                    return URLSessionAIProvider(
                        kind: settings.aiProvider,
                        baseURL: settings.baseURL,
                        apiKey: apiKey,
                        timeoutSeconds: TimeInterval(settings.aiRequestTimeoutSeconds)
                    )
                },
                aiSettingsProvider: {
                    let settings = try repositories.appSettings.fetch()
                    return ProcessingAISettings(
                        modelName: settings.modelName,
                        maxArticlesPerScan: settings.maxArticlesPerScan,
                        maxArticlesPerTopicBatch: settings.maxArticlesPerTopicBatch
                    )
                }
            )
        )
        candidateTopicManagementUseCase = CandidateTopicManagementUseCase(repositories: repositories)
    }

    func makeTopicBriefGenerationUseCase() throws -> TopicBriefGenerationUseCase {
        TopicBriefGenerationUseCase(
            repositories: repositories,
            generator: TopicBriefGenerationService(provider: try makeAIProvider())
        )
    }

    private func makeAIProvider() throws -> URLSessionAIProvider {
        let settings = try repositories.appSettings.fetch()
        guard let accountIdentifier = settings.keychainAccountIdentifier else {
            throw AIProviderError.missingAPIKey
        }
        guard let apiKey = try keychainStore.readAPIKey(accountIdentifier: accountIdentifier) else {
            throw AIProviderError.missingAPIKey
        }
        return URLSessionAIProvider(
            kind: settings.aiProvider,
            baseURL: settings.baseURL,
            apiKey: apiKey,
            timeoutSeconds: TimeInterval(settings.aiRequestTimeoutSeconds)
        )
    }

    static func defaultDatabasePath() -> String {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return applicationSupportURL
            .appendingPathComponent("RSSRadar", isDirectory: true)
            .appendingPathComponent("rssradar.sqlite")
            .path
    }
}

enum AppBootstrap {
    case ready(AppEnvironment)
    case failed(String)

    static func make() -> AppBootstrap {
        do {
            return .ready(try AppEnvironment())
        } catch {
            return .failed(String(describing: error))
        }
    }
}
