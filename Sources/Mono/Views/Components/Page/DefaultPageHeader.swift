import SwiftUI

struct DefaultHeaderActionLabel: View {
    let icon: MonoIcon.IconType
    let title: String
    var color: Color = .monoTextPrimary

    var body: some View {
        MonoIcon(icon: icon, size: 18, color: color, lineWidth: 1.7)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityShowsLargeContentViewer {
                Text(title)
            }
    }
}
