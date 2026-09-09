import Foundation

/// Variants of the system-navigation setting, separate from the twelve floating-player styles.
enum SystemTabBarStyle: String, CaseIterable, Identifiable {
    case native
    case monoDock
    case monoSplit

    var id: String { rawValue }
    var usesCustomLayout: Bool { self != .native }

    var title: String {
        switch self {
        case .native: String(localized: "system_tab_bar_native")
        case .monoDock: String(localized: "system_tab_bar_dock")
        case .monoSplit: String(localized: "system_tab_bar_split")
        }
    }
}
