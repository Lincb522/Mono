import SwiftUI

@MainActor
struct DatabaseRootView<Content: View>: View {
    @ObservedObject private var database = DatabaseManager.shared
    @ObservedObject private var store = DatabaseManager.shared.store
    @State private var showsSaveError = false
    @ViewBuilder let content: @MainActor () -> Content

    var body: some View {
        Group {
            if database.initializationError != nil {
                VStack(spacing: 16) {
                    Text("database_open_failed_title").font(.headline)
                    Text("database_open_failed_message")
                        .multilineTextAlignment(.center)
                    Button("action_retry") { database.retryInitialization() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content()
            }
        }
        .onReceive(store.$saveError) { error in
            showsSaveError = error != nil
        }
        .alert("database_save_failed_title", isPresented: $showsSaveError) {
            Button("action_retry") { database.save() }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("database_save_failed_message")
        }
    }
}
