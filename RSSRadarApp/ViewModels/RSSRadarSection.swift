import Foundation

enum RSSRadarSection: String, CaseIterable, Identifiable {
    case today
    case topics
    case feeds
    case processing
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .today:
            "Today"
        case .topics:
            "Topics"
        case .feeds:
            "Feeds"
        case .processing:
            "Processing"
        case .settings:
            "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "sparkles"
        case .topics:
            "rectangle.stack"
        case .feeds:
            "dot.radiowaves.left.and.right"
        case .processing:
            "gearshape.2"
        case .settings:
            "slider.horizontal.3"
        }
    }
}
