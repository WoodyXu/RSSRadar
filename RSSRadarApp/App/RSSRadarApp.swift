import AppKit
import SwiftUI

@main
struct RSSRadarApp: App {
    private let bootstrap = AppBootstrap.make()

    init() {
        if let url = Bundle.module.url(forResource: "icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case let .ready(environment):
                AppRootView(environment: environment)
            case let .failed(message):
                BootstrapFailureView(message: message)
            }
        }
    }
}

private struct BootstrapFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RSSRadar 无法启动")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
    }
}
