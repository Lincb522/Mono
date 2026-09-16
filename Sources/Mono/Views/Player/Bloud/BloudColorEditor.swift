import SwiftUI
import UIKit

/// Present from the character sheet so editing never replaces its navigation or scroll state.
struct BloudColorEditor: View {
    let title: String
    @Binding var selection: Color
    @State private var draft: Color
    @Environment(\.dismiss) private var dismiss

    init(title: String, selection: Binding<Color>) {
        self.title = title
        self._selection = selection
        self._draft = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            BloudNativeColorPicker(selection: Binding(
                get: { draft },
                set: { color in
                    // Persistence may quantize to HEX; never feed that value back into the live picker.
                    draft = color
                    selection = color
                }
            ))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { dismiss() }
                    }
                }
        }
    }
}

private struct BloudNativeColorPicker: UIViewControllerRepresentable {
    @Binding var selection: Color

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(selection)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.selection = $selection
        let color = UIColor(selection)
        if !picker.selectedColor.isEqual(color) { picker.selectedColor = color }
    }

    @MainActor
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var selection: Binding<Color>

        init(selection: Binding<Color>) { self.selection = selection }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            selection.wrappedValue = Color(uiColor: viewController.selectedColor)
        }
    }
}
