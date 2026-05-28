import Foundation
import RSSRadarCore
import RSSRadarProcessing

@MainActor
final class FeedsViewModel: ObservableObject {
    @Published var feedURLString = ""
    @Published var feeds: [Feed] = []
    @Published var articlesByFeedID: [String: [Article]] = [:]
    @Published var isWorking = false
    @Published var statusMessage = "内容源已就绪。"
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func load() {
        runSync {
            try refreshSnapshot()
            statusMessage = feeds.isEmpty ? noFeedsMessage : "已保存 \(feeds.count) 个内容源。"
        }
    }

    func addManualFeed() async {
        await run {
            let feed = try await self.environment.manualFeedAddUseCase.addFeed(urlString: self.feedURLString)
            self.feedURLString = ""
            try self.refreshSnapshot()
            self.statusMessage = "已添加 \(feed.title)。"
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
            try refreshSnapshot()
            statusMessage = """
                已导入 \(result.importedFeeds.count) 个内容源。\
                跳过 \(result.skippedDuplicates.count) 个重复源，错误 \(result.errors.count) 个。
                """
        }
    }

    func refresh(feed: Feed) async {
        await run {
            let articleCountBefore = try self.environment.repositories.articles.fetch(feedID: feed.id).count
            try await self.enqueueExistingParsedArticlesIfConfigured()
            _ = try await self.environment.processingEngine.enqueueFeedScan(feedID: feed.id)
            await self.environment.processingEngine.runPendingJobsUntilIdle()
            try self.refreshSnapshot()
            let articleCountAfter = self.articlesByFeedID[feed.id, default: []].count
            if articleCountAfter == articleCountBefore {
                self.statusMessage = """
                    \(feed.title) 暂无新文章。最近一次扫描完成于 \(Date().appShortDate)。
                    """
            } else {
                self.statusMessage = """
                    已刷新 \(feed.title)，新增 \(articleCountAfter - articleCountBefore) 篇文章。
                    """
            }
        }
    }

    func refreshAll() async {
        await run {
            guard !self.feeds.isEmpty else {
                self.statusMessage = self.noFeedsMessage
                return
            }

            let articleCountBefore = try self.environment.repositories.articles.fetchAll().count
            try await self.enqueueExistingParsedArticlesIfConfigured()
            _ = try await self.environment.processingEngine.enqueueScanAllFeeds()
            await self.environment.processingEngine.runPendingJobsUntilIdle()
            try self.refreshSnapshot()
            let articleCountAfter = self.articlesByFeedID.values.reduce(0) { $0 + $1.count }
            if articleCountAfter == articleCountBefore {
                self.statusMessage = "暂无新文章。所有正常内容源已更新至 \(Date().appShortDate)。"
            } else {
                self.statusMessage = "已刷新全部内容源，新增 \(articleCountAfter - articleCountBefore) 篇文章。"
            }
        }
    }

    func setPaused(_ paused: Bool, feed: Feed) {
        runSync {
            var updatedFeed = feed
            updatedFeed.status = paused ? .paused : .active
            updatedFeed.updatedAt = Date()
            try environment.repositories.feeds.save(updatedFeed)
            try refreshSnapshot()
            statusMessage = paused ? "已暂停 \(feed.title)。" : "已恢复 \(feed.title)。"
        }
    }

    func delete(feed: Feed) {
        runSync {
            try environment.repositories.feeds.delete(id: feed.id)
            try refreshSnapshot()
            statusMessage = feeds.isEmpty ? noFeedsMessage : "已删除 \(feed.title)。"
        }
    }

    func rssSummaryFallbackCount(for feed: Feed) -> Int {
        articlesByFeedID[feed.id, default: []].filter { $0.contentSource == .rssSummary }.count
    }

    private var noFeedsMessage: String {
        "暂无 RSS 源。请导入 OPML 或添加 RSS URL 后开始扫描。"
    }

    private func refreshSnapshot() throws {
        feeds = try environment.repositories.feeds.fetchAll()
        articlesByFeedID = try environment.repositories.articles.fetchGroupedByFeedID()
    }

    private func enqueueExistingParsedArticlesIfConfigured() async throws {
        let settings = try environment.repositories.appSettings.fetch()
        guard settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        _ = try await environment.processingEngine.enqueueParsedArticleAnalysis(
            modelName: settings.modelName,
            maxArticles: settings.maxArticlesPerScan
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
