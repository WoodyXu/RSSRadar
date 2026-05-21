import SwiftUI

struct AppRootView: View {
    @State private var selection: RSSRadarSection? = .today

    var body: some View {
        NavigationSplitView {
            List(RSSRadarSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
            }
            .navigationTitle("RSSRadar")
        } detail: {
            switch selection {
            case .today:
                PlaceholderView(title: "Today")
            case .topics:
                PlaceholderView(title: "Topics")
            case .feeds:
                PlaceholderView(title: "Feeds")
            case .processing:
                PlaceholderView(title: "Processing")
            case .settings:
                PlaceholderView(title: "Settings")
            case .none:
                PlaceholderView(title: "Today")
            }
        }
    }
}

private struct PlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.92)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(red: 0, green: 0.38, blue: 0.25))

                Text("RSSRadar MVP workspace")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)
        }
    }
}
