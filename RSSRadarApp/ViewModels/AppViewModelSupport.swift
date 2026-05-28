import Foundation
import RSSRadarCore

enum AppViewModelErrorMessage {
    static func message(from error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

extension FeedStatus {
    var appDisplayName: String {
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

extension ProcessingJobType {
    var displayName: String {
        switch self {
        case .fetchFeed:
            "内容源扫描"
        case .parseArticle:
            "文章解析"
        case .analyzeArticle:
            "文章分析"
        case .assignTopics:
            "主题归类"
        case .generateTopicBrief:
            "主题情报页"
        case .retryFailedJob:
            "失败任务重试"
        }
    }
}

extension ProcessingJobStatus {
    var displayName: String {
        switch self {
        case .pending:
            "等待中"
        case .running:
            "运行中"
        case .completed:
            "已完成"
        case .failed:
            "失败"
        }
    }
}

extension TopicStatus {
    var appDisplayName: String {
        switch self {
        case .candidate:
            "待确认主题"
        case .active:
            "跟踪主题"
        case .ignored:
            "忽略主题"
        case .archived:
            "归档主题"
        }
    }
}

extension ScanMode: Identifiable {
    public var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .manual:
            "手动"
        case .onLaunch:
            "启动时"
        case .interval:
            "每 N 小时"
        }
    }
}
