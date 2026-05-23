import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 0.95, green: 0.94, blue: 0.92)
    static let ceramic = Color(red: 0.93, green: 0.92, blue: 0.91)
    static let green = Color(red: 0, green: 0.38, blue: 0.25)
    static let accentGreen = Color(red: 0, green: 0.46, blue: 0.29)
    static let houseGreen = Color(red: 0.12, green: 0.22, blue: 0.20)
    static let danger = Color(red: 0.78, green: 0.13, blue: 0.08)
}

struct AppCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 0.5)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.accentGreen)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(AppTheme.accentGreen)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay {
                Capsule().stroke(AppTheme.accentGreen, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct AppDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.danger)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct PageStatusBanner: View {
    let message: String
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
            }
        }
    }
}

struct EmptyStateCard<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actions: Actions

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accentGreen)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.green)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
