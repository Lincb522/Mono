import SwiftUI

private struct ElasticSettingsSwitchPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var elasticSettingsSwitchPressed: Bool {
        get { self[ElasticSettingsSwitchPressedKey.self] }
        set { self[ElasticSettingsSwitchPressedKey.self] = newValue }
    }
}

struct ElasticSettingsSwitchButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.elasticSettingsSwitchPressed, configuration.isPressed)
    }
}

struct ElasticSettingsRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(ElasticSettingsSwitchButtonStyle())
    }
}

// Adapted from the switch by _2944 on Uiverse.io, scaled to the existing settings row.
struct ElasticSettingsSwitch: View {
    let isOn: Bool

    static var isActiveForCurrentTheme: Bool {
        let theme = GlobalThemeId.persistedOrDefault
        return theme == .default || theme == .clarity
    }

    @ObservedObject private var colorEngine = UnifiedColorEngine.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.elasticSettingsSwitchPressed) private var isPressed
    @State private var isHovering = false
    @State private var pulseID = 0

    private let height: CGFloat = 32
    private var width: CGFloat { height * 4 / 2.2 }
    private var diameter: CGFloat { height * 1.8 / 2.2 }
    private var inset: CGFloat { (height - diameter) / 2 }
    private var isDark: Bool { colorScheme == .dark }
    private var stretches: Bool { isPressed && isEnabled && !reduceMotion }
    private var accent: Color { colorEngine.colors.accent }

    private var knobWidth: CGFloat { stretches ? width - inset * 2 : diameter }

    private var knobOffset: CGFloat {
        let travel = (width - diameter) / 2
        let offset = stretches ? 0 : (isOn ? travel : -travel)
        return layoutDirection == .rightToLeft ? -offset : offset
    }

    private var offGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: "3A3A3A"), Color(hex: "2A2A2A")]
                : [Color(hex: "E8E8E8"), Color(hex: "D4D4D4")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var onGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(reduceTransparency ? 1 : 0.82), accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var knobGradient: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [Color(hex: "555555"), Color(hex: "444444")]
                : [.white, Color(hex: isOn ? "F5F5F5" : "F0F0F0")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            track
            stateMarks
            knob
        }
        .frame(width: width, height: height)
        .fixedSize()
        .overlay {
            if isOn && pulseID > 0 && isEnabled && !reduceMotion && !reduceTransparency {
                ElasticSettingsSwitchPulse(color: accent)
                    .id(pulseID)
            }
        }
        .overlay {
            if isFocused {
                Capsule()
                    .inset(by: -3)
                    .stroke(accent, lineWidth: 2)
            }
        }
        .saturation(isEnabled ? 1 : 0.7)
        .onHover { isHovering = $0 }
        .onChange(of: isOn) { _, newValue in
            if newValue && isEnabled && !reduceMotion && !reduceTransparency {
                pulseID &+= 1
            }
        }
        .accessibilityHidden(true)
    }

    private var track: some View {
        ZStack {
            Capsule()
                .fill(offGradient.shadow(.inner(
                    color: .black.opacity(isDark ? 0.5 : 0.2), radius: 2, x: 1, y: 1
                )))
            Capsule()
                .fill(onGradient.shadow(.inner(color: .black.opacity(0.15), radius: 2, x: 1, y: 1)))
                .opacity(isOn ? 1 : 0)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(isDark ? 0.15 : 0.65), .black.opacity(0.08)],
                        startPoint: .bottomTrailing,
                        endPoint: .topLeading
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(isDark ? Color.white : Color.black, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isDark ? 0.2 : 0.08), radius: 1, x: 0, y: 1)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.4), value: isOn)
    }

    private var stateMarks: some View {
        HStack {
            Image(systemName: "checkmark")
                .foregroundStyle(colorEngine.onAccent)
                .opacity(isOn ? 1 : 0)
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .foregroundStyle(isDark ? Color.white.opacity(0.7) : Color.black.opacity(0.5))
                .opacity(isOn ? 0 : 1)
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 9)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.3), value: isOn)
    }

    private var knob: some View {
        Capsule()
            .fill(knobGradient)
            .overlay {
                Capsule().strokeBorder(
                    contrast == .increased
                        ? (isDark ? Color.white : Color.black)
                        : .white.opacity(isDark ? 0.12 : 0.8),
                    lineWidth: contrast == .increased ? 1 : 0.5
                )
            }
            .frame(width: knobWidth, height: diameter)
            .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 2, x: 0, y: 2)
            .shadow(color: accent.opacity(isOn && !reduceTransparency ? 0.4 : 0), radius: 5, x: 0, y: 1)
            .scaleEffect(isHovering && isEnabled && !isPressed && !reduceMotion ? 1.05 : 1)
            .offset(x: knobOffset)
            .animation(
                reduceMotion ? .linear(duration: 0.1) : .timingCurve(0.68, -0.55, 0.265, 1.55, duration: 0.5),
                value: isOn
            )
            .animation(
                reduceMotion ? .linear(duration: 0.1) : (stretches
                    ? .easeOut(duration: 0.3)
                    : .timingCurve(0.68, -0.55, 0.265, 1.55, duration: 0.5)),
                value: stretches
            )
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

private struct ElasticSettingsSwitchPulse: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        Capsule()
            .stroke(color, lineWidth: 2)
            .scaleEffect(x: expanded ? 1.3 : 1, y: expanded ? 1.5 : 1)
            .opacity(expanded ? 0 : 0.5)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    expanded = true
                }
            }
    }
}
