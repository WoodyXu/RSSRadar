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

extension ProcessingJobType {
    var displayName: String {
        switch self {
        case .fetchFeed:
            "Feed scan"
        case .parseArticle:
            "Article parsing"
        case .analyzeArticle:
            "Article analysis"
        case .assignTopics:
            "Topic assignment"
        case .generateTopicBrief:
            "Topic brief"
        case .retryFailedJob:
            "Failed-job retry"
        }
    }
}

extension ProcessingJobStatus {
    var displayName: String {
        switch self {
        case .pending:
            "pending"
        case .running:
            "running"
        case .completed:
            "completed"
        case .failed:
            "failed"
        }
    }
}

extension TopicStatus {
    var appDisplayName: String {
        switch self {
        case .candidate:
            "candidate"
        case .active:
            "active"
        case .ignored:
            "ignored"
        case .archived:
            "archived"
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
            "Manual"
        case .onLaunch:
            "On launch"
        case .interval:
            "Every N hours"
        }
    }
}
