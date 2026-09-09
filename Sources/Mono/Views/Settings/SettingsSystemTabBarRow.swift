import SwiftUI

struct SettingsSystemTabBarRow: View {
    @Binding var selection: SystemTabBarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings_system_tab_bar_style"))
                .font(themedSettingsFont(13, weight: .medium))
                .foregroundStyle(Color.monoTextSecondary)
                .padding(.bottom, 4)
            ForEach(SystemTabBarStyle.allCases) { style in
                Button { selection = style } label: {
                    HStack(spacing: 12) {
                        Text(style.title)
                            .font(themedSettingsFont(16, weight: .medium))
                            .foregroundStyle(Color.monoTextPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: selection == style ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(selection == style ? Color.monoAccent : Color.monoTextSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == style ? .isSelected : [])
                .accessibilityIdentifier("settings.systemTabBar.\(style.rawValue)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
