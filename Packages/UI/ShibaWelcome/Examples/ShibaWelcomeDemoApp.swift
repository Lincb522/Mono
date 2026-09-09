import SwiftUI
import ShibaWelcome

// Use this as your app's entry point; keep only ONE @main App in the app target.
@main
struct ShibaWelcomeDemoApp: App {
    var body: some Scene {
        WindowGroup { DemoRootView() }
    }
}

private struct DemoRootView: View {
    @State private var hasEntered = false

    var body: some View {
        if hasEntered {
            VStack(spacing: 20) {
                Text("已进入应用").font(.title2)
                Button("返回欢迎页") { hasEntered = false }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ShibaWelcomeScreen {
                hasEntered = true
            }
        }
    }
}
