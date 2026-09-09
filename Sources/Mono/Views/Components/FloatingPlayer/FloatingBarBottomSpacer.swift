import Combine
import SwiftUI

/// Bottom spacer for pages that scroll behind the custom floating bar.
/// It stays compact when the mini player is collapsed, and grows just enough
/// to keep the final action row tappable when a song is playing.
struct FloatingBarBottomSpacer: View {
    var extra: CGFloat = 0
    @ScaledMetric(relativeTo: .caption2) private var monoDockHeight: CGFloat = 162
    @ScaledMetric(relativeTo: .caption2) private var instrumentScale: CGFloat = 1

    @AppStorage("useSystemTabBar") private var useSystemTabBar = false
    @AppStorage("systemTabBarStyle") private var systemTabBarStyleRaw = SystemTabBarStyle.native.rawValue
    @AppStorage("floatingBarStyle") private var floatingBarStyleRaw = FloatingBarStyle.unified.rawValue
    @AppStorage("globalThemeId") private var globalThemeIdRaw = GlobalThemeId.appDefault.rawValue
    @State private var isTabBarHidden = PlayerManager.shared.isTabBarHidden
    @State private var hasCurrentSong = PlayerManager.shared.currentSong != nil

    var body: some View {
        Color.clear
            .frame(height: max(0, baseHeight + extra))
            .accessibilityHidden(true)
            .onReceive(PlayerManager.shared.$isTabBarHidden.removeDuplicates()) { hidden in
                isTabBarHidden = hidden
            }
            .onReceive(PlayerManager.shared.$currentSong.map { $0 != nil }.removeDuplicates()) { hasCurrentSong in
                self.hasCurrentSong = hasCurrentSong
            }
    }

    private var baseHeight: CGFloat {
        guard !isTabBarHidden else { return 24 }

        if useSystemTabBar, SystemTabBarStyle(rawValue: systemTabBarStyleRaw)?.usesCustomLayout == true {
            return monoDockHeight
        }

        if useSystemTabBar && globalThemeId != .manga {
            return hasCurrentSong ? 72 : 20
        }

        if floatingBarStyle.isSignatureStyle {
            return hasCurrentSong ? (SignatureFloatingBarKind(style: floatingBarStyle).activeHeight + 28) * instrumentScale : 88
        }

        if globalThemeId == .clarity {
            switch floatingBarStyle {
            case .unified:
                return hasCurrentSong ? 150 : 136
            case .classic:
                return hasCurrentSong ? 148 : 82
            case .minimal:
                return hasCurrentSong ? 124 : 70
            case .floatingBall:
                return 140
            default:
                return hasCurrentSong ? 176 : 108
            }
        }

        if globalThemeId == .manga {
            return hasCurrentSong ? 174 : 104
        }

        switch floatingBarStyle {
        case .unified:
            if globalThemeId == .neumorphic {
                return hasCurrentSong ? 176 : 108
            }
            if !hasCurrentSong {
                return isThemedPageActive ? 88 : 80
            }
            return isThemedPageActive ? 152 : 142

        case .classic:
            return hasCurrentSong ? 130 : 70

        case .minimal:
            return hasCurrentSong ? 112 : 88

        case .floatingBall:
            return 88

        case .flux, .liquid:
            return hasCurrentSong ? 112 : 94

        case .cassette, .orbit, .vinylNeedle, .waveform, .filmstrip, .studioMeter:
            return hasCurrentSong ? (SignatureFloatingBarKind(style: floatingBarStyle).activeHeight + 28) * instrumentScale : 88
        }
    }

    private var floatingBarStyle: FloatingBarStyle {
        FloatingBarStyle(rawValue: floatingBarStyleRaw) ?? .flux
    }

    private var globalThemeId: GlobalThemeId {
        GlobalThemeId.resolvedStoredTheme(globalThemeIdRaw)
    }

    private var isThemedPageActive: Bool {
        globalThemeId != .default
    }
}
