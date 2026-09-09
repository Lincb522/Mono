import SwiftUI

public struct ShibaWelcomeScreen: View {
    private let title: String
    private let subtitle: String
    private let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var replayToken = 0

    public init(
        title: String = "很高兴见到你",
        subtitle: String = "准备好，一起出发。",
        onContinue: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onContinue = onContinue
    }

    public var body: some View {
        ZStack {
            background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    ShibaMascotView(action: .welcome, replayToken: replayToken)
                        .frame(maxWidth: 300)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    Button(action: onContinue) {
                        Text("开始使用")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(accent)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.top, 12)

                    Button("再打个招呼") { replayToken += 1 }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var background: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.125, blue: 0.106)
            : Color(red: 1, green: 0.969, blue: 0.914)
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.769, blue: 0.408)
            : Color(red: 0.169, green: 0.141, blue: 0.110)
    }
}
