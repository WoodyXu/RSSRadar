import Foundation

enum RSSRadarSection: String, CaseIterable, Identifiable, Hashable {
    case topics
    case feeds
    case processing
    case settings

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .topics:
            "主题聚合"
        case .feeds:
            "内容源配置"
        case .processing:
            "处理日志"
        case .settings:
            "通用配置"
        }
    }

    var systemImage: String {
        switch self {
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
