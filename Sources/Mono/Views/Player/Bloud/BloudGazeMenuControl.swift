import SwiftUI

/// Optional BLOUD controls embedded in the shared three-dot menu.
struct BloudGazeMenuControl: View {
    @Binding var isEnabled: Bool
    var needsSettings: Bool
    var failure: BloudCameraFailure?
    var palette: MonoMoreMenuPalette? = nil
    var onRecovery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isEnabled) {
                Text("player_bloud_gaze_follow")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle((palette?.text ?? Color.monoTextPrimary))
            }
            .tint(palette?.accent ?? .monoAccent)
            .frame(minHeight: 44)
            .accessibilityHint(Text("player_bloud_gaze_follow_hint"))

            if isEnabled, needsSettings || failure != nil {
                Text(LocalizedStringKey(needsSettings ? "player_bloud_camera_permission" : (failure?.rawValue ?? "")))
                    .font(.caption)
                    .foregroundStyle((palette?.secondary ?? Color.monoTextSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Button(needsSettings ? String(localized: "player_bloud_camera_settings")
                                     : String(localized: "player_bloud_camera_retry"),
                       action: onRecovery)
                    .font(.subheadline)
                    .foregroundStyle((palette?.text ?? Color.monoTextPrimary))
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
    }
}
