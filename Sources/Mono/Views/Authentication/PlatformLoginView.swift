import SwiftUI
import UIKit
import QQMusicKit

enum PlatformLoginSource: String, CaseIterable, Identifiable {
    case ncm
    case qcm
    case kcm

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var musicSource: MusicSource {
        switch self {
        case .ncm: return .netease
        case .qcm: return .qqmusic
        case .kcm: return .kugou
        }
    }
}

private enum NCMLoginMethod: String, CaseIterable, Identifiable {
    case qrCode
    case phone

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .qrCode: "login_method_qr"
        case .phone: "login_method_phone"
        }
    }
}

private enum NCMPhoneLoginField: Hashable {
    case countryCode
    case phone
    case captcha
}

struct PlatformLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var ncmViewModel = LoginViewModel()
    @StateObject private var qcmViewModel = QQLoginViewModel()
    @StateObject private var kcmViewModel = KCMLoginViewModel()

    @State private var selectedPlatform: PlatformLoginSource
    @State private var didFinishLogin = false
    @State private var dismissTask: Task<Void, Never>?
    @State private var loginCompletionID: UUID?
    @State private var ncmLoginMethod: NCMLoginMethod = .qrCode
    @FocusState private var focusedPhoneField: NCMPhoneLoginField?

    init(initialPlatform: PlatformLoginSource = .ncm) {
        _selectedPlatform = State(initialValue: initialPlatform)
    }

    var body: some View {
        let _ = settings.globalThemeRevision

        ZStack {
            ThemedPageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    if SignalStyle.isActive {
                        SignalNestedPageHeader(
                            title: String(localized: "platform_login_title"),
                            eyebrow: String(localized: "settings_eyebrow_accounts"),
                            icon: .personCircle,
                            module: .accounts
                        )
                    }

                    platformPicker
                    if selectedPlatform == .ncm {
                        ncmLoginMethodPicker
                    }
                    if selectedPlatform == .qcm {
                        qcmLoginModePicker
                    }
                    if selectedPlatform == .ncm, ncmLoginMethod == .phone {
                        phoneLoginPanel
                    } else {
                        qrCodePanel
                        statusRow
                    }
                }
                .padding(.horizontal, DeviceLayout.viewHorizontalPadding)
                .padding(.top, 28)
                .padding(.bottom, 48)
                .iPadContentWidth(520)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .monoNavigationBackButton()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "common_done")) {
                    focusedPhoneField = nil
                }
            }
        }
        .onAppear(perform: startSelectedLogin)
        .onDisappear {
            cancelPendingDismiss()
            stopAllLoginWork()
        }
        .onChange(of: selectedPlatform) { _, _ in
            cancelPendingDismiss()
            didFinishLogin = false
            focusedPhoneField = nil
            suspendAllLoginWork()
            startSelectedLogin()
        }
        .onChange(of: ncmLoginMethod) { _, method in
            guard selectedPlatform == .ncm else { return }
            cancelPendingDismiss()
            didFinishLogin = false
            focusedPhoneField = nil
            switch method {
            case .qrCode:
                ncmViewModel.cancelPhoneRequests()
                ncmViewModel.startQRLogin()
            case .phone:
                ncmViewModel.stopQRPolling()
            }
        }
        .onChange(of: ncmViewModel.captchaCooldownRemaining) { previous, remaining in
            if previous == 0,
               remaining > 0,
               selectedPlatform == .ncm,
               ncmLoginMethod == .phone {
                focusedPhoneField = .captcha
            }
        }
        .onChange(of: ncmViewModel.phoneFeedback) { _, feedback in
            guard selectedPlatform == .ncm,
                  ncmLoginMethod == .phone,
                  let feedback else { return }
            UIAccessibility.post(notification: .announcement, argument: feedback.message)
        }
        .onChange(of: ncmViewModel.isLoggedIn) { _, loggedIn in
            if loggedIn { finishLogin(for: .ncm) }
        }
        .onChange(of: qcmViewModel.isLoggedIn) { _, loggedIn in
            if loggedIn { finishLogin(for: .qcm) }
        }
        .onChange(of: kcmViewModel.isLoggedIn) { _, loggedIn in
            if loggedIn { finishLogin(for: .kcm) }
        }
    }

    private var platformPicker: some View {
        HStack(spacing: 8) {
            ForEach(PlatformLoginSource.allCases) { platform in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedPlatform = platform
                    }
                } label: {
                    HStack(spacing: 7) {
                        PlatformBadgeLabel(
                            text: platform.musicSource.shortName,
                            source: platform.musicSource,
                            fontSize: 9
                        )

                        Text(platform.title)
                            .font(
                                SignalStyle.isActive
                                    ? .system(
                                        .subheadline,
                                        design: .default,
                                        weight: selectedPlatform == platform ? .bold : .medium
                                    )
                                    : .system(.subheadline, design: .rounded, weight: .semibold)
                            )
                    }
                    .foregroundStyle(
                        SignalStyle.isActive
                            ? (selectedPlatform == platform ? SignalStyle.onAccent : SignalStyle.inkSoft)
                            : (selectedPlatform == platform ? Color.monoTextPrimary : Color.monoTextSecondary)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                SignalStyle.isActive
                                    ? (selectedPlatform == platform ? SignalStyle.accent : SignalStyle.control)
                                    : (selectedPlatform == platform ? platform.musicSource.themedBadgeColor.opacity(0.14) : Color.clear)
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
                .accessibilityLabel(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "platform_login_switch_accessibility",
                            comment: "Platform sign-in switch accessibility label"
                        ),
                        platform.title
                    )
                )
                .accessibilityAddTraits(selectedPlatform == platform ? .isSelected : [])
            }
        }
        .padding(4)
        .themedPageSurface(cornerRadius: 16, elevated: false, mangaTint: MangaStyle.bubbleWhite)
    }

    private var ncmLoginMethodPicker: some View {
        Picker(LocalizedStringKey("login_method_accessibility"), selection: $ncmLoginMethod) {
            ForEach(NCMLoginMethod.allCases) { method in
                Text(method.title).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(Text(LocalizedStringKey("login_method_accessibility")))
    }

    private var qcmLoginModePicker: some View {
        HStack(spacing: 8) {
            qcmLoginModeButton(
                title: String(localized: "qcm_login_mode_qq"),
                type: .qq
            )
            qcmLoginModeButton(
                title: String(localized: "qcm_login_mode_wechat"),
                type: .wx
            )
        }
        .padding(4)
        .themedPageSurface(cornerRadius: 14, elevated: false, mangaTint: MangaStyle.bubbleWhite)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "qcm_login_mode"))
    }

    private func qcmLoginModeButton(title: String, type: QRLoginType) -> some View {
        let selected = qcmViewModel.qrLoginType == type
        return Button {
            guard !selected else { return }
            cancelPendingDismiss()
            didFinishLogin = false
            withAnimation(.easeOut(duration: 0.2)) {
                qcmViewModel.switchQRType(type)
            }
        } label: {
            Text(title)
                .font(
                    SignalStyle.isActive
                        ? .system(
                            .subheadline,
                            design: .default,
                            weight: selected ? .bold : .medium
                        )
                        : .system(.subheadline, design: .rounded, weight: .semibold)
                )
                .foregroundStyle(SignalStyle.isActive ? (selected ? SignalStyle.onAccent : SignalStyle.inkSoft) : (selected ? Color.monoTextPrimary : Color.monoTextSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            SignalStyle.isActive
                                ? (selected ? SignalStyle.accent : SignalStyle.control)
                                : (selected ? MusicSource.qqmusic.themedBadgeColor.opacity(0.14) : Color.clear)
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var phoneLoginPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey("login_phone_number"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phoneSecondaryText)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            countryCodeField(maxWidth: .infinity)

                            Rectangle()
                                .fill(phoneInputBorder)
                                .frame(height: 0.5)

                            phoneNumberField
                        }
                    } else {
                        HStack(spacing: 10) {
                            countryCodeField(maxWidth: 82)

                            Rectangle()
                                .fill(phoneInputBorder)
                                .frame(width: 0.5, height: 22)

                            phoneNumberField
                        }
                    }
                }
                .font(.body.weight(.medium))
                .foregroundStyle(phonePrimaryText)
                .monoTextInputBehavior()
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(phoneInputSurface)
                .disabled(phoneFieldsDisabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey("login_captcha"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(phoneSecondaryText)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        captchaTextField
                            .frame(minWidth: 136)
                            .layoutPriority(1)
                        sendCaptchaButton
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(spacing: 10) {
                        captchaTextField
                        sendCaptchaButton
                    }
                }
            }

            Button {
                focusedPhoneField = nil
                ncmViewModel.loginWithPhone()
            } label: {
                HStack(spacing: 8) {
                    if ncmViewModel.isPhoneLoggingIn {
                        ProgressView()
                            .tint(phoneActionText)
                    }

                    Text(LocalizedStringKey(
                        ncmViewModel.isPhoneLoggingIn ? "login_phone_logging_in" : "login_phone_action"
                    ))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(phoneActionText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background {
                    RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.buttonRadius : 14, style: .continuous)
                        .fill(phoneActionBackground)
                }
            }
            .buttonStyle(MonoBouncingButtonStyle(scale: 0.97))
            .disabled(!ncmViewModel.canLoginWithPhone)
            .opacity(ncmViewModel.canLoginWithPhone ? 1 : 0.48)

            if let feedback = ncmViewModel.phoneFeedback {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: phoneFeedbackIcon(feedback))
                        .accessibilityHidden(true)

                    Text(feedback.message)
                        .multilineTextAlignment(.leading)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(phoneFeedbackColor(feedback))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(SignalStyle.isActive ? 16 : 18)
        .themedPageSurface(cornerRadius: SignalStyle.isActive ? SignalStyle.cardRadius : 20, elevated: false, mangaTint: MangaStyle.bubbleWhite)
    }

    private func countryCodeField(maxWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text("+")
                .foregroundStyle(phoneSecondaryText)

            TextField(LocalizedStringKey("login_country_code_placeholder"), text: $ncmViewModel.countryCode)
                .focused($focusedPhoneField, equals: .countryCode)
                .keyboardType(.numberPad)
                .accessibilityLabel(Text(LocalizedStringKey("login_country_code")))
        }
        .frame(minWidth: 54, maxWidth: maxWidth, alignment: .leading)
    }

    private var phoneNumberField: some View {
        TextField(LocalizedStringKey("login_phone_placeholder"), text: $ncmViewModel.phoneNumber)
            .focused($focusedPhoneField, equals: .phone)
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
            .submitLabel(.next)
            .onSubmit { focusedPhoneField = .captcha }
            .accessibilityLabel(Text(LocalizedStringKey("login_phone_number")))
    }

    private var captchaTextField: some View {
        TextField(LocalizedStringKey("login_captcha_placeholder"), text: $ncmViewModel.phoneCaptcha)
            .focused($focusedPhoneField, equals: .captcha)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .submitLabel(.go)
            .onSubmit {
                if ncmViewModel.canLoginWithPhone {
                    focusedPhoneField = nil
                    ncmViewModel.loginWithPhone()
                }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(phonePrimaryText)
            .monoTextInputBehavior()
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(phoneInputSurface)
            .disabled(phoneFieldsDisabled)
            .accessibilityLabel(Text(LocalizedStringKey("login_captcha")))
    }

    private var sendCaptchaButton: some View {
        Button {
            ncmViewModel.sendPhoneCaptcha()
        } label: {
            HStack(spacing: 7) {
                if ncmViewModel.isSendingCaptcha {
                    ProgressView()
                        .controlSize(.small)
                        .tint(phonePrimaryText)
                }

                Text(captchaButtonTitle)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(phonePrimaryText)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background {
                RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.buttonRadius : 14, style: .continuous)
                    .fill(phoneSecondaryActionBackground)
            }
        }
        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
        .disabled(!ncmViewModel.canSendCaptcha)
        .opacity(ncmViewModel.canSendCaptcha ? 1 : 0.48)
    }

    private var captchaButtonTitle: String {
        if ncmViewModel.isSendingCaptcha {
            return String(localized: "login_captcha_sending")
        }
        if ncmViewModel.captchaCooldownRemaining > 0 {
            return String.localizedStringWithFormat(
                NSLocalizedString("login_captcha_resend_countdown", comment: "Captcha resend countdown"),
                ncmViewModel.captchaCooldownRemaining
            )
        }
        return String(localized: "login_captcha_send")
    }

    private var phoneInputSurface: some View {
        RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.buttonRadius : 14, style: .continuous)
            .fill(phoneInputBackground)
            .overlay {
                RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.buttonRadius : 14, style: .continuous)
                    .stroke(phoneInputBorder, lineWidth: 0.8)
            }
    }

    private var phoneInputBackground: Color {
        SignalStyle.isActive ? SignalStyle.control : Color.monoTextPrimary.opacity(0.055)
    }

    private var phoneFieldsDisabled: Bool {
        ncmViewModel.isSendingCaptcha || ncmViewModel.isPhoneLoggingIn
    }

    private var phoneInputBorder: Color {
        SignalStyle.isActive ? SignalStyle.separator.opacity(0.78) : Color.monoSeparator.opacity(0.72)
    }

    private var phonePrimaryText: Color {
        SignalStyle.isActive ? SignalStyle.ink : Color.monoTextPrimary
    }

    private var phoneSecondaryText: Color {
        SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary
    }

    private var phoneActionBackground: Color {
        SignalStyle.isActive ? SignalStyle.accent : Color.monoIconBackground
    }

    private var phoneActionText: Color {
        SignalStyle.isActive ? SignalStyle.onAccent : Color.monoIconForeground
    }

    private var phoneSecondaryActionBackground: Color {
        SignalStyle.isActive ? SignalStyle.control : Color.monoSeparator.opacity(0.34)
    }

    private func phoneFeedbackIcon(_ feedback: PhoneLoginFeedback) -> String {
        switch feedback {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.circle.fill"
        }
    }

    private func phoneFeedbackColor(_ feedback: PhoneLoginFeedback) -> Color {
        switch feedback {
        case .success: phonePrimaryText
        case .failure: Color.red.opacity(0.88)
        }
    }

    private var qrCodePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.cardRadius : 20, style: .continuous)
                .fill(Color.white)

            if let image = qrCodeImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(22)
            } else {
                ProgressView()
                    .tint(selectedPlatform.musicSource.themedBadgeColor)
            }

            if isQRExpired {
                RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.cardRadius : 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Button(action: refreshQRCode) {
                            VStack(spacing: 10) {
                                MonoIcon(icon: .refresh, size: 24, color: .monoTextPrimary)
                                Text(LocalizedStringKey("qr_refresh_action"))
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.monoTextPrimary)
                            }
                            .padding(20)
                        }
                        .buttonStyle(MonoBouncingButtonStyle(scale: 0.96))
                    }
            }
        }
        .frame(width: 244, height: 244)
        .overlay {
            RoundedRectangle(cornerRadius: SignalStyle.isActive ? SignalStyle.cardRadius : 20, style: .continuous)
                .stroke(SignalStyle.isActive ? SignalStyle.separator.opacity(0.78) : Color.monoSeparator.opacity(0.75), lineWidth: 0.8)
        }
        .accessibilityElement(children: isQRExpired ? .contain : .ignore)
        .accessibilityLabel(qrCodeAccessibilityLabel)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            MonoStatusBeacon(
                kind: qrStatusKind,
                tint: selectedPlatform.musicSource.themedBadgeColor,
                size: 7
            )

            Text(qrStatusMessage)
                .font(
                    SignalStyle.isActive
                        ? .system(.subheadline, design: .monospaced, weight: .medium)
                        : .system(.subheadline, design: .rounded, weight: .medium)
                )
                .foregroundStyle(SignalStyle.isActive ? SignalStyle.inkSoft : Color.monoTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var qrCodeImage: UIImage? {
        switch selectedPlatform {
        case .ncm: return ncmViewModel.qrCodeImage
        case .qcm: return qcmViewModel.qrCodeImage
        case .kcm: return kcmViewModel.qrCodeImage
        }
    }

    private var qrStatusMessage: String {
        switch selectedPlatform {
        case .ncm: return ncmViewModel.qrStatusMessage
        case .qcm: return qcmViewModel.qrStatusMessage
        case .kcm: return kcmViewModel.qrStatusMessage
        }
    }

    private var isQRExpired: Bool {
        switch selectedPlatform {
        case .ncm: return ncmViewModel.isQRExpired
        case .qcm: return qcmViewModel.isQRExpired
        case .kcm: return kcmViewModel.isQRExpired
        }
    }

    private var qrStatusKind: MonoStatusKind {
        if isQRExpired { return .failed }

        let status = qrStatusMessage.lowercased()
        if status.contains("成功") || status.contains("success") {
            return .success
        }
        if status.contains("已扫码")
            || status.contains("scanned")
            || status.contains("确认")
            || status.contains("confirm") {
            return .scanned
        }
        if status.contains("拒绝")
            || status.contains("失败")
            || status.contains("异常")
            || status.contains("refused")
            || status.contains("failed")
            || status.contains("could not")
            || status.contains("error") {
            return .failed
        }
        if qrCodeImage != nil
            || status.contains("加载")
            || status.contains("等待")
            || status.contains("重试")
            || status.contains("loading")
            || status.contains("waiting")
            || status.contains("retry") {
            return .active
        }
        return .idle
    }

    private var qrCodeAccessibilityLabel: String {
        let format = NSLocalizedString(
            "qr_login_accessibility",
            comment: "Platform sign-in QR code accessibility label"
        )
        if selectedPlatform == .qcm {
            let mode = qcmViewModel.qrLoginType == .qq
                ? String(localized: "qcm_login_mode_qq")
                : String(localized: "qcm_login_mode_wechat")
            return String.localizedStringWithFormat(format, mode)
        }
        return String.localizedStringWithFormat(format, selectedPlatform.title)
    }

    private func startSelectedLogin() {
        switch selectedPlatform {
        case .ncm:
            if ncmLoginMethod == .qrCode {
                ncmViewModel.startQRLogin()
            }
        case .qcm: qcmViewModel.startQRLogin()
        case .kcm: kcmViewModel.startQRLogin()
        }
    }

    private func refreshQRCode() {
        switch selectedPlatform {
        case .ncm: ncmViewModel.refreshQR()
        case .qcm: qcmViewModel.refreshQR()
        case .kcm: kcmViewModel.refreshQR()
        }
    }

    private func suspendAllLoginWork() {
        ncmViewModel.suspendLoginWork()
        qcmViewModel.stopPolling()
        kcmViewModel.stopPolling()
    }

    private func stopAllLoginWork() {
        ncmViewModel.stopLoginWork()
        qcmViewModel.stopPolling()
        kcmViewModel.stopPolling()
    }

    private func finishLogin(for platform: PlatformLoginSource) {
        guard selectedPlatform == platform, !didFinishLogin else { return }
        guard LoginIdentityManager.shared.select(platform.musicSource) else { return }
        cancelPendingDismiss()
        let completionID = UUID()
        loginCompletionID = completionID
        didFinishLogin = true
        stopAllLoginWork()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled,
                  didFinishLogin,
                  selectedPlatform == platform,
                  loginCompletionID == completionID else { return }
            dismissTask = nil
            loginCompletionID = nil
            dismiss()
        }
    }

    private func cancelPendingDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        loginCompletionID = nil
    }
}

#Preview {
    NavigationStack {
        PlatformLoginView(initialPlatform: .kcm)
    }
}
