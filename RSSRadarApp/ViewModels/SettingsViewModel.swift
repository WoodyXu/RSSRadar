import Foundation
import RSSRadarCore
import RSSRadarPersistence

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedProvider: AIProviderKind = .openAICompatible {
        didSet {
            if selectedProvider != oldValue {
                baseURLString = selectedProvider.defaultBaseURL.absoluteString
            }
        }
    }
    @Published var baseURLString = AIProviderKind.openAICompatible.defaultBaseURL.absoluteString
    @Published var modelName = ""
    @Published var apiKey = ""
    @Published var scanMode: ScanMode = .manual
    @Published var scanIntervalHours = 6
    @Published var maxArticlesPerScan = 100
    @Published var maxArticlesForNewFeed = 20
    @Published var maxArticlesPerTopicBatch = 20
    @Published var aiRequestTimeoutSeconds = 120
    @Published var databasePath = AppEnvironment.defaultDatabasePath()
    @Published var hasSavedAPIKey = false
    @Published var savedProviderName = "未配置"
    @Published var savedBaseURLString = "未配置"
    @Published var savedModelName = "未配置"
    @Published var deleteAPIKeyWhenClearing = false
    @Published var clearConfirmationText = ""
    @Published var isWorking = false
    @Published var statusMessage = "通用配置已就绪。"
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() {
        runSync {
            let settings = try environment.repositories.appSettings.fetch()
            applyAISettings(settings: settings)
            applyScanSettings(settings: settings)
            applyDataSettings(settings: settings)
            statusMessage = "配置已加载。"
        }
    }

    func saveAISettings() {
        runSync {
            guard let baseURL = URL(string: baseURLString), baseURL.scheme?.isEmpty == false else {
                throw SettingsViewModelError.invalidBaseURL
            }

            var settings = try environment.repositories.appSettings.fetch()
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAPIKey.isEmpty {
                let account = settings.keychainAccountIdentifier ?? KeychainAPIKeyStore.makeAccountIdentifier()
                try environment.keychainStore.saveAPIKey(trimmedAPIKey, accountIdentifier: account)
                settings.keychainAccountIdentifier = account
            }

            settings.aiProvider = selectedProvider
            settings.baseURL = baseURL
            settings.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            try environment.repositories.appSettings.save(settings)

            apiKey = ""
            applyAISettings(settings: settings)
            statusMessage = "AI 配置已保存。"
        }
    }

    func saveScanSettings() {
        runSync {
            var settings = try environment.repositories.appSettings.fetch()
            settings.scanMode = scanMode
            settings.scanIntervalHours = max(1, scanIntervalHours)
            settings.maxArticlesPerScan = max(1, maxArticlesPerScan)
            settings.maxArticlesForNewFeed = max(1, maxArticlesForNewFeed)
            settings.maxArticlesPerTopicBatch = max(1, maxArticlesPerTopicBatch)
            settings.aiRequestTimeoutSeconds = max(5, aiRequestTimeoutSeconds)
            try environment.repositories.appSettings.save(settings)

            applyScanSettings(settings: settings)
            statusMessage = "扫描与成本配置已保存。"
        }
    }

    func saveDataSettings() {
        runSync {
            var settings = try environment.repositories.appSettings.fetch()
            settings.databasePath = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
            try environment.repositories.appSettings.save(settings)

            applyDataSettings(settings: settings)
            statusMessage = "数据配置已保存。"
        }
    }

    func deleteSavedAPIKey() {
        runSync {
            var settings = try environment.repositories.appSettings.fetch()
            if let account = settings.keychainAccountIdentifier {
                try environment.keychainStore.deleteAPIKey(accountIdentifier: account)
            }
            settings.keychainAccountIdentifier = nil
            try environment.repositories.appSettings.save(settings)
            applyAISettings(settings: settings)
            statusMessage = "已删除保存的 API Key。"
        }
    }

    func clearLocalData() {
        runSync {
            guard canClearLocalData else {
                throw SettingsViewModelError.confirmationRequired
            }

            let settings = try environment.repositories.appSettings.fetch()
            try environment.repositories.performTransaction { transaction in
                for correction in try transaction.userCorrections.fetchAll() {
                    try transaction.userCorrections.delete(id: correction.id)
                }
                for job in try transaction.processingJobs.fetchAll() {
                    try transaction.processingJobs.delete(id: job.id)
                }
                for log in try transaction.operationLogs.fetchAll() {
                    try transaction.operationLogs.delete(id: log.id)
                }
                for topic in try transaction.topics.fetchAll() {
                    try transaction.topics.delete(id: topic.id)
                }
                for feed in try transaction.feeds.fetchAll() {
                    try transaction.feeds.delete(id: feed.id)
                }
            }

            if deleteAPIKeyWhenClearing, let account = settings.keychainAccountIdentifier {
                try environment.keychainStore.deleteAPIKey(accountIdentifier: account)
                var updatedSettings = settings
                updatedSettings.keychainAccountIdentifier = nil
                try environment.repositories.appSettings.save(updatedSettings)
                hasSavedAPIKey = false
            }

            clearConfirmationText = ""
            deleteAPIKeyWhenClearing = false
            statusMessage = "本地业务数据已清空。"
        }
    }

    var canClearLocalData: Bool {
        clearConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "CLEAR"
    }

    private func applyAISettings(settings: AppSettings) {
        selectedProvider = settings.aiProvider
        baseURLString = settings.baseURL.absoluteString
        modelName = settings.modelName
        hasSavedAPIKey = settings.keychainAccountIdentifier != nil
        savedProviderName = settings.aiProvider.displayName
        savedBaseURLString = settings.baseURL.absoluteString
        savedModelName = settings.modelName.isEmpty ? "未配置" : settings.modelName
    }

    private func applyScanSettings(settings: AppSettings) {
        scanMode = settings.scanMode
        scanIntervalHours = settings.scanIntervalHours
        maxArticlesPerScan = settings.maxArticlesPerScan
        maxArticlesForNewFeed = settings.maxArticlesForNewFeed
        maxArticlesPerTopicBatch = settings.maxArticlesPerTopicBatch
        aiRequestTimeoutSeconds = settings.aiRequestTimeoutSeconds
    }

    private func applyDataSettings(settings: AppSettings) {
        databasePath = settings.databasePath ?? AppEnvironment.defaultDatabasePath()
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

private enum SettingsViewModelError: Error, LocalizedError {
    case invalidBaseURL
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效。"
        case .confirmationRequired:
            "请输入 CLEAR 确认清空本地数据。"
        }
    }
}
