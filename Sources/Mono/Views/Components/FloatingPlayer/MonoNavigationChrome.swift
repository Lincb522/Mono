import SwiftUI

enum MonoNavigationLayout {
    case native
    case unified
    case separated
}

enum MonoNavigationChrome {
    static let accent = Color(red: 0.84, green: 0.18, blue: 0.14)
    static let darkAccent = Color(red: 1, green: 0.36, blue: 0.31)
}

extension Tab {
    func navigationIcon(isLocalMode: Bool, selected: Bool = false) -> MonoIcon.IconType {
        if self == .podcast && isLocalMode { return .musicNote }
        return selected ? icon : monoIcon
    }

    func navigationSymbol(isLocalMode: Bool, selected: Bool = false) -> String {
        switch self {
        case .home: return selected ? "house.fill" : "house"
        case .podcast: return isLocalMode ? "music.note" : "dot.radiowaves.left.and.right"
        case .library: return selected ? "square.stack.fill" : "square.stack"
        case .profile: return selected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }
}

struct MonoNavigationSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(colorScheme == .dark ? Color(white: 0.11) : .white)
                } else {
                    shape.fill(.regularMaterial)
                        .overlay {
                            shape.fill(colorScheme == .dark
                                ? Color(white: 0.10).opacity(0.62)
                                : Color.white.opacity(0.60))
                        }
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 16, x: 0, y: 7)
    }
}

struct MonoNavigationTabs: View {
    @Binding var selection: Tab
    let layout: MonoNavigationLayout
    let isLocalMode: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 10.0
    @Namespace private var selectionNamespace

    private var accent: Color {
        colorScheme == .dark ? MonoNavigationChrome.darkAccent : MonoNavigationChrome.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    guard !selected else { return }
                    HapticManager.shared.light()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        MonoIcon(
                            icon: tab.navigationIcon(isLocalMode: isLocalMode, selected: selected),
                            size: 22,
                            color: selected && layout == .unified ? accent : .primary,
                            normalizesBitmapScale: true
                        )
                            .frame(height: 25)
                        Text(LocalizedStringKey(tab.titleKey(isLocalMode: isLocalMode)))
                            .font(.system(size: labelSize, weight: selected ? .semibold : .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: labelSize * 1.25)
                        ZStack {
                            Color.clear
                            if selected {
                                Capsule().fill(accent)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .frame(width: 16, height: 3)
                    }
                    .foregroundStyle(selected && layout == .unified ? accent : Color.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(tab.titleKey(isLocalMode: isLocalMode))))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("mono.tab.\(tab.rawValue)")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: selection)
    }
}
