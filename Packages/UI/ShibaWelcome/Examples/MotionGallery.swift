import SwiftUI
import ShibaWelcome

struct MotionGallery: View {
    @State private var action: ShibaAction = .welcome
    @State private var replayToken = 0

    var body: some View {
        VStack(spacing: 20) {
            ShibaMascotView(action: action, replayToken: replayToken)
                .frame(width: 280, height: 280)

            Picker("动作", selection: $action) {
                ForEach(ShibaAction.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)

            Button("重播") { replayToken += 1 }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }
}

#Preview("动作预览") {
    MotionGallery()
}
