import SwiftUI

@main
struct RSSRadarApp: App {
    private let bootstrap = AppBootstrap.make()

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
            Text("RSSRadar could not start")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(32)
    }
}
