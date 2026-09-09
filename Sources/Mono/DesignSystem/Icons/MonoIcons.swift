import SwiftUI
import HiconIcons
import ZappiconIcons
import LucideIcons
import SolarIcons
import BlobIcons
import doodlePop
import PawPrintIcons
import DotDogSnakeIcons
import MinimalWhiteIcons
import PulseBloomIcons
import MonoGlyphIcons

// MARK: - 统一图标系统

private struct MonoIconDarkArtworkSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MonoIconArtworkKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    fileprivate var monoIconDarkArtworkSurface: Bool {
        get { self[MonoIconDarkArtworkSurfaceKey.self] }
        set { self[MonoIconDarkArtworkSurfaceKey.self] = newValue }
    }

    fileprivate var monoIconArtwork: String? {
        get { self[MonoIconArtworkKey.self] }
        set { self[MonoIconArtworkKey.self] = newValue }
    }
}

extension View {
    /// 为玻璃菜单、封面舞台等“界面仍是浅色模式、局部表面却是深色”的区域
    /// 显式选择支持深色外观图标包的白边资源。系统深色模式不需要调用此修饰器。
    func monoIconDarkArtworkSurface(_ enabled: Bool = true) -> some View {
        environment(\.monoIconDarkArtworkSurface, enabled)
    }

    func monoIconArtwork(_ assetId: String?) -> some View {
        environment(\.monoIconArtwork, assetId)
    }
}

enum MonoGlyphSemantic: String {
    case copy
    case rename
    case link
    case gift
    case trendUp
    case trendDown
    case volumeMute
    case volumeLow
    case volumeMedium
    case volumeHigh
    case gestureSwipeHorizontal
    case gestureTap
    case maintenance
    case policyDocument
    case quote
    case selectionCircle
    case instrumentalLyrics
    case gameMode
    case gameModePower
    case gamePresetFPS
    case gamePresetRPG
    case gamePresetRhythm
    case gameVoicePriority
    case gameLowerQuality
    case gameAutoExit
    case gameSilentNowPlaying
    case gameMinimalNowPlaying
    case gamePreferredQuality
    case gameAutoPlaylist
    case soundCenter
    case soundWorkspaceAI
    case soundWorkspaceCustomEQ
    case soundWorkspaceEnhancement
    case soundWorkspaceOutput
    case audioAgent
    case agentAutoTuning
    case agentAdaptiveLearning
    case agentPlayerStatus
    case agentSkillMeasurement
    case agentSkillDeviceCoordination
    case agentSkillHeadroomGuard
    case agentSkillPhaseGuard
    case agentSkillOutputValidation
    case agentSkillArtistReference
    case agentSkillVocalReference
    case agentCustomSkill
    case agentManagedSkill
    case agentAddCustomSkill
    case agentEditCustomSkill
    case aiTuningWorkspace
    case aiMeasurementWorkspace
    case aiResultWorkspace
    case aiHistoryWorkspace
    case agentAnalyze
    case agentStopAnalysis
    case agentReanalyze
    case agentApplySavedProposal
    case learningEnabled
    case learningStrength
    case learningRetention
    case learningSourceFeedback
    case learningSourceListening
    case learningSourceAdjustments
    case learningLocalStorage
    case learningFeedbackPositive
    case learningFeedbackNegative
    case learningFeedbackRetained
    case learningFeedbackReset
    case learningFeedbackRegenerated
    case learningFeedbackManualEQ
    case agentTraceRoot
    case agentTraceOverview
    case agentExecutionChain
    case agentCurrentSkills
    case agentToolContract
    case agentRuntimeResult
    case agentRuntimeIdentity
    case agentRawRecords
    case agentTraceStageConfiguration
    case agentTraceStageSkills
    case agentTraceStageMeasurement
    case agentTraceStageModel
    case agentTraceStageTool
    case agentTraceStageValidation
    case agentTraceStageCompilation
    case agentTraceStageApplication
    case agentTraceStageFallback
    case agentTraceStageCompletion
}

enum MonoIconArtworkContrast {
    static func prefersLightArtwork(
        on background: Color,
        colorScheme: ColorScheme
    ) -> Bool {
        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let lightContrast = ThemeColorCustomization.contrastRatio(
            between: .white,
            and: background,
            interfaceStyle: interfaceStyle
        )
        let darkContrast = ThemeColorCustomization.contrastRatio(
            between: .black,
            and: background,
            interfaceStyle: interfaceStyle
        )
        return lightContrast >= darkContrast
    }
}

struct MonoSemanticIcon: View {
    let semantic: MonoGlyphSemantic
    let fallback: MonoIcon.IconType
    var size: CGFloat = 24
    var color: Color = .primary
    var lineWidth: CGFloat? = nil

    var body: some View {
        MonoIcon(icon: fallback, size: size, color: color, lineWidth: lineWidth)
            .monoIconArtwork(semantic.rawValue)
    }
}

/// 根据用户选择的图标包，将统一语义图标映射为对应的矢量或位图资源。
struct MonoIcon: View {
    enum IconType {
        case home
        case homeFilled
        case podcast
        case podcastFilled
        case library
        case libraryFilled
        case search
        case profile
        case profileFilled
        
        case play
        case pause
        case next
        case previous
        case stop
        case repeatMode
        case repeatOne
        case shuffle
        case refresh
        
        case like
        case liked
        case list
        case back
        case more
        case close
        case trash
        case fm
        case bell
        
        case settings
        case download
        case cloud
        case chevronRight
        case chevronLeft
        case chevronDown
        case chevronUp
        case magnifyingGlass
        case xmark
        case fullscreen
        case sparkle
        case soundQuality
        case storage
        case haptic
        case info
        
        case clock
        case musicNoteList
        case chart
        case translate
        case karaoke
        case lock
        case unlock
        case qr
        case phone
        case send
        case musicNote
        case save
        
        case playerDownload
        case comment
        
        case history
        case playCircle
        case warning
        case personEmpty
        case playNext
        case add
        case addToQueue
        
        case radio
        case micSlash
        case waveform
        case skipBack
        case skipForward
        case rewind15
        case forward15
        case xmarkCircle
        case playCircleFill
        case gridSquare
        
        case checkmark
        case shrinkScreen
        case expandScreen
        case headphones
        case heartSlash
        case personCircle
        case album
        case infoCircle
        case arrowDownCircle
        case sun
        case moon
        case halfCircle
        
        case equalizer
        case immersive
        case playerTheme
        
        case catMusic
        case catLife
        case catEmotion
        case catCreate
        case catAcg
        case catEntertain
        case catTalkshow
        case catBook
        case catKnowledge
        case catBusiness
        case catHistory
        case catNews
        case catParenting
        case catTravel
        case catCrosstalk
        case catFood
        case catTech
        case catDefault
        case catPodcast
        case catElectronic
        case catStar
        case catDrama
        case catStory
        case catOther
        case catPublish
        
        case emoji
        
        case share
        case logInfo
        case logDebug
        case logError
        case logNetwork
        case logSuccess
        case arrowDownToLine
        
        case filter
        case microphone
        case fmMode
        case audioWave
        
        case mv
        case layers
        case hitokoto
        case tabBar
        case minimalBar
        case floatingBall
    }
    
    let icon: IconType
    var size: CGFloat = 24
    var color: Color = .primary
    var lineWidth: CGFloat? = nil
    var normalizesBitmapScale: Bool = false
    /// 需要参与渐变遮罩或动态前景色计算时，强制把彩色图标包按模板渲染。
    /// 默认关闭，避免改变其他页面原有的彩色图标外观。
    var forceTemplateRendering: Bool = false
    /// Tab 等带选中底色的控件传入实际底色后，支持明暗资源的图标包会按
    /// 对比度选黑图或白图，而不是跟随 App 的明暗外观。
    var artworkContrastBackground: Color? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.monoIconDarkArtworkSurface) private var isDarkArtworkSurface
    @Environment(\.monoIconArtwork) private var artworkId
    @AppStorage(AppConfig.StorageKeys.interfaceIconSet) private var iconSetRaw: String = AppInterfaceIconSet.hicon.rawValue
    @AppStorage(AppInterfaceIconSet.zappiconStyleKey) private var zappiconStyleRaw: String = ZappiconIconStyle.light.rawValue
    @AppStorage(AppInterfaceIconSet.solarStyleKey) private var solarStyleRaw: String = SolarIconStyle.line.rawValue
    @AppStorage(AppInterfaceIconSet.monoGlyphStyleKey) private var monoGlyphStyleRaw: String = MonoGlyphIconStyle.classic.rawValue
    
    var body: some View {
        Group {
            if icon == .liked {
                likedIcon
            } else {
                iconImage
            }
        }
        .frame(width: size, height: size)
        .foregroundColor(color)
    }

    private var iconSet: AppInterfaceIconSet {
        _ = iconSetRaw
        return AppInterfaceIconSet.selectedFromDefaults
    }

    /// 当前图标的 UIImage — 根据图标集和风格动态选择
    private var currentImage: UIImage {
        switch iconSet {
        case .hicon:
            return icon.hiconImage
        case .sfSymbols:
            return icon.sfSymbolImage
        case .zappicon:
            let style = ZappiconIconStyle(rawValue: zappiconStyleRaw) ?? .light
            return icon.zappiconImage(style: style)
        case .lucide:
            return icon.lucideImage
        case .solar:
            let style = SolarIconStyle(rawValue: solarStyleRaw) ?? .line
            return icon.solarImage(style: style)
        case .blobIcons:
            return icon.blobIconImage
        case .doodlePop:
            return icon.doodlePopImage(prefersLightOutline: usesLightAdaptiveOutline)
        case .pawPrint:
            return icon.pawPrintImage(prefersLightOutline: usesLightAdaptiveOutline)
        case .dotDogSnake:
            return icon.dotDogSnakeImage(prefersLightOutline: usesLightAdaptiveOutline)
        case .minimalWhiteIcons:
            return icon.minimalWhiteIconImage(prefersLightOutline: usesLightAdaptiveOutline)
        case .pulseBloom:
            return icon.pulseBloomImage(
                assetId: artworkId,
                prefersLightOutline: usesLightAdaptiveOutline
            )
        case .monoGlyph:
            return icon.monoGlyphImage(
                assetId: artworkId,
                prefersLightOutline: usesLightAdaptiveOutline,
                style: MonoGlyphIconStyle(rawValue: monoGlyphStyleRaw) ?? .classic
            )
        }
    }

    private var usesOriginalArtwork: Bool {
        iconSet.usesOriginalArtwork
    }

    private var rendersOriginalArtwork: Bool {
        guard usesOriginalArtwork else { return false }

        if iconSet == .pulseBloom || iconSet == .monoGlyph {
            return true
        }
        return !forceTemplateRendering
    }

    private var usesBitmapVisualScale: Bool {
        iconSet == .blobIcons || iconSet == .doodlePop || iconSet == .pawPrint || iconSet == .dotDogSnake || iconSet == .minimalWhiteIcons || iconSet == .pulseBloom || iconSet == .monoGlyph
    }

    private var bitmapIconVisualScale: CGFloat {
        switch iconSet {
        case .minimalWhiteIcons:
            return 1.18
        case .pulseBloom, .monoGlyph:
            return 1.08
        case .doodlePop, .pawPrint, .dotDogSnake:
            switch icon {
            case .karaoke:
                return 1.58
            case .translate:
                return 1.48
            default:
                return 1.45
            }
        case .blobIcons:
            return 1.36
        default:
            return 1
        }
    }

    private var effectiveBitmapVisualScale: CGFloat {
        guard usesBitmapVisualScale, !normalizesBitmapScale else { return 1 }
        return bitmapIconVisualScale
    }

    private var usesLightAdaptiveOutline: Bool {
        if let artworkContrastBackground {
            return MonoIconArtworkContrast.prefersLightArtwork(
                on: artworkContrastBackground,
                colorScheme: colorScheme
            )
        }

        if isDarkArtworkSurface { return true }

        // Tab controls already resolve their foreground against the actual
        // selected fill. Honor that black/white result before the app-wide
        // appearance so a white accent in dark mode receives the dark asset.
        if isPrimaryTabNavigationIcon,
           let requestedVariant = requestedNeutralArtworkVariant {
            return requestedVariant
        }

        if iconSet == .monoGlyph {
            if colorScheme == .dark { return true }
            if isPrimaryTabNavigationIcon { return false }
            return requestedNeutralArtworkVariant ?? false
        }

        if iconSet == .pulseBloom {
            if colorScheme == .dark { return true }
            if isPrimaryTabNavigationIcon { return false }
            return requestedColorPrefersLightArtwork
        }

        return colorScheme == .dark
    }

    private var isPrimaryTabNavigationIcon: Bool {
        switch icon {
        case .home, .homeFilled,
             .podcast, .podcastFilled,
             .musicNote, .musicNoteList,
             .library, .libraryFilled,
             .profile, .profileFilled:
            return true
        default:
            return false
        }
    }

    /// For monochrome artwork, the requested foreground color also signals the
    /// expected contrast on cover-driven surfaces. A
    /// light foreground means the surface behind it is expected to be dark and
    /// therefore selects the white-outline artwork even while the app itself is
    /// still in light mode.
    private var requestedColorPrefersLightArtwork: Bool {
        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: interfaceStyle)
        let resolvedColor = UIColor(color).resolvedColor(with: traits)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            return luminance >= 0.56
        }

        var white: CGFloat = 0
        if resolvedColor.getWhite(&white, alpha: &alpha) {
            return white >= 0.56
        }

        return colorScheme == .dark
    }

    /// `true` selects the light artwork, `false` the dark artwork, and `nil`
    /// leaves colored/non-neutral foregrounds to the normal surface rules.
    private var requestedNeutralArtworkVariant: Bool? {
        let interfaceStyle: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: interfaceStyle)
        let resolvedColor = UIColor(color).resolvedColor(with: traits)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
            let chroma = max(red, max(green, blue)) - min(red, min(green, blue))
            guard chroma <= 0.14 else { return nil }
            if luminance >= 0.64 { return true }
            if luminance <= 0.36 { return false }
            return nil
        }

        var white: CGFloat = 0
        if resolvedColor.getWhite(&white, alpha: &alpha) {
            if white >= 0.64 { return true }
            if white <= 0.36 { return false }
        }

        return nil
    }

    private var iconImage: some View {
        rawIconImage(currentImage)
    }

    private func rawIconImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .interpolation(.high)
            .antialiased(true)
            .renderingMode(rendersOriginalArtwork ? .original : .template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(effectiveBitmapVisualScale)
    }
    
    @ViewBuilder
    private var likedIcon: some View {
        if rendersOriginalArtwork {
            rawIconImage(currentImage)
        } else {
            ZStack {
                Image(uiImage: iconSet.image(for: .like))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color.opacity(0.25))
                Image(uiImage: iconSet.image(for: .liked))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(color)
            }
            .scaleEffect(effectiveBitmapVisualScale)
        }
    }
}

/// Compatibility layer for older call sites that used SF Symbol names.
/// This intentionally renders through the app icon system so new UI does not depend on SF Symbols.
struct MonoSymbolIcon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color = .primary
    var lineWidth: CGFloat? = nil

    var body: some View {
        if name == "circle" {
            Circle()
                .stroke(color, lineWidth: lineWidth ?? 1.7)
                .frame(width: size, height: size)
        } else if name == "checkmark.circle.fill" {
            ZStack {
                Circle().fill(color)
                MonoIcon(icon: .checkmark, size: size * 0.56, color: .white, lineWidth: lineWidth)
            }
            .frame(width: size, height: size)
        } else if name == "quote.opening" || name == "text.quote" {
            Text("“")
                .font(.system(size: size * 1.25, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: size, height: size)
        } else if AppInterfaceIconSet.selectedFromDefaults == .pawPrint, name == "chevron.down" {
            MonoPawPrintChevronIcon(direction: .down, size: size, fallbackColor: color)
        } else if AppInterfaceIconSet.selectedFromDefaults == .pawPrint, name == "chevron.up" {
            MonoPawPrintChevronIcon(direction: .up, size: size, fallbackColor: color)
        } else {
            let mapping = MonoIcon.IconType.fromSystemName(name)
            MonoIcon(icon: mapping.icon, size: size, color: color, lineWidth: lineWidth)
                .rotationEffect(mapping.rotation)
        }
    }
}

private struct MonoPawPrintChevronIcon: View {
    enum Direction {
        case up
        case down

        var assetName: String {
            switch self {
            case .up: return "chevronUp"
            case .down: return "chevronDown"
            }
        }

        var fallbackSystemName: String {
            switch self {
            case .up: return "chevron.up"
            case .down: return "chevron.down"
            }
        }
    }

    let direction: Direction
    var size: CGFloat
    var fallbackColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.monoIconDarkArtworkSurface) private var isDarkArtworkSurface

    var body: some View {
        platformImage
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var platformImage: some View {
        if let image = resolvedImage {
            Image(uiImage: image)
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackIcon
        }
    }

    private var resolvedImage: UIImage? {
        if colorScheme == .dark || isDarkArtworkSurface {
            return UIImage(pawPrintIconId: direction.assetName, userInterfaceStyle: .dark)
        }
        return UIImage(pawPrintIconId: direction.assetName)
    }

    private var fallbackIcon: some View {
        let mapping = MonoIcon.IconType.fromSystemName(direction.fallbackSystemName)
        return MonoIcon(icon: mapping.icon, size: size, color: fallbackColor)
            .rotationEffect(mapping.rotation)
    }
}

// MARK: - IconType → Hicon Mapping

extension MonoIcon.IconType {
    static func fromSystemName(_ name: String) -> (icon: MonoIcon.IconType, rotation: Angle) {
        switch name {
        case "house.fill":
            return (.homeFilled, .zero)
        case "mic.fill", "music.mic":
            return (.microphone, .zero)
        case "square.stack.3d.up.fill", "square.grid.2x2", "square.grid.2x2.fill", "rectangle.stack.fill":
            return (.gridSquare, .zero)
        case "person.fill", "person.2", "person.2.fill", "person.crop.circle.badge.questionmark":
            return (.profileFilled, .zero)
        case "music.note":
            return (.musicNote, .zero)
        case "music.note.list", "list.bullet":
            return (.musicNoteList, .zero)
        case "magnifyingglass":
            return (.magnifyingGlass, .zero)
        case "gearshape.fill":
            return (.settings, .zero)
        case "radio", "dot.radiowaves.left.and.right":
            return (.radio, .zero)
        case "heart", "heart.fill":
            return (.liked, .zero)
        case "star.fill", "star":
            return (.sparkle, .zero)
        case "play.fill", "play.circle.fill":
            return (.play, .zero)
        case "pause.fill":
            return (.pause, .zero)
        case "backward.fill", "backward.end.alt.fill":
            return (.previous, .zero)
        case "forward.fill", "forward.end.alt.fill":
            return (.next, .zero)
        case "chevron.right":
            return (.chevronRight, .zero)
        case "chevron.left":
            return (.chevronLeft, .zero)
        case "chevron.down":
            return (.chevronRight, .degrees(90))
        case "chevron.up":
            return (.chevronRight, .degrees(-90))
        case "ellipsis", "ellipsis.bubble.fill":
            return (.more, .zero)
        case "xmark", "xmark.circle.fill":
            return (.close, .zero)
        case "arrow.down.circle.fill":
            return (.arrowDownCircle, .zero)
        case "arrow.trianglehead.2.clockwise":
            return (.refresh, .zero)
        case "repeat":
            return (.repeatMode, .zero)
        case "repeat.1":
            return (.repeatOne, .zero)
        case "shuffle":
            return (.shuffle, .zero)
        case "waveform":
            return (.waveform, .zero)
        case "tv", "film", "play.tv":
            return (.immersive, .zero)
        case "bubble.left.fill", "bubble.left.and.bubble.right.fill":
            return (.comment, .zero)
        case "cart":
            return (.download, .zero)
        case "trash":
            return (.trash, .zero)
        case "sun.max.fill":
            return (.sun, .zero)
        case "moon.fill":
            return (.moon, .zero)
        case "pencil.and.outline", "hand.draw":
            return (.save, .zero)
        default:
            return (.sparkle, .zero)
        }
    }

    var hiconImage: UIImage {
        switch self {
        // Tab Bar / Navigation
        case .home:             return Hicon.home1
        case .homeFilled:       return Hicon.home2
        case .podcast:          return Hicon.microphone3
        case .podcastFilled:    return Hicon.microphone4
        case .library:          return Hicon.headphone1
        case .libraryFilled:    return Hicon.headphone2
        case .search:           return Hicon.search1
        case .profile:          return Hicon.profile1
        case .profileFilled:    return Hicon.profile1
        
        // Playback Controls
        case .play:             return Hicon.play
        case .pause:            return Hicon.pause
        case .next:             return Hicon.next
        case .previous:         return Hicon.previous
        case .stop:             return Hicon.stop
        case .repeatMode:       return Hicon.repeate1
        case .repeatOne:        return Hicon.repeateOne1
        case .shuffle:          return Hicon.shuffle1
        case .refresh:          return Hicon.refresh1
        
        // Actions
        case .like:             return Hicon.heart2
        case .liked:            return Hicon.heart2
        case .list:             return Hicon.menuHamburger
        case .back:             return Hicon.left2
        case .more:             return Hicon.menuMeatballs
        case .close:            return Hicon.close
        case .trash:            return Hicon.delete1
        case .fm:               return Hicon.radio
        case .bell:             return Hicon.notification1
        
        // Settings & Utility
        case .settings:         return Hicon.setting
        case .download:         return Hicon.download
        case .cloud:            return Hicon.upload
        case .chevronRight:     return Hicon.right2
        case .chevronLeft:      return Hicon.left2
        case .chevronDown:      return Hicon.down2
        case .chevronUp:        return Hicon.up2
        case .magnifyingGlass:  return Hicon.search1
        case .xmark:            return Hicon.close
        case .fullscreen:       return Hicon.zoomIn
        case .sparkle:          return Hicon.star1
        case .soundQuality:     return Hicon.voiceShape1
        case .storage:          return Hicon.flashDisk1
        case .haptic:           return Hicon.activity1
        case .info:             return Hicon.informationCircle
        
        // Media Info
        case .clock:            return Hicon.timeCircle1
        case .musicNoteList:    return Hicon.musicnote
        case .chart:            return Hicon.chart
        case .translate:        return Hicon.text
        case .karaoke:          return Hicon.microphone1
        case .lock:             return Hicon.lock1
        case .unlock:           return Hicon.unlock1
        case .qr:               return Hicon.scan1
        case .phone:            return Hicon.call
        case .send:             return Hicon.send1
        case .musicNote:        return Hicon.music
        case .save:             return Hicon.bookmark1
        
        // Player
        case .playerDownload:   return Hicon.download
        case .comment:          return Hicon.message1
        
        // Library
        case .history:          return Hicon.timeCircle3
        case .playCircle:       return Hicon.playCircle
        case .warning:          return Hicon.dangerTriangle
        case .personEmpty:      return Hicon.profile1
        case .playNext:         return Hicon.addCategory
        case .add:              return Hicon.add
        case .addToQueue:       return Hicon.addCategory
        
        // Podcast
        case .radio:            return Hicon.radio
        case .micSlash:         return Hicon.microphoneOff
        case .waveform:         return Hicon.voiceShape1
        case .skipBack:         return Hicon.backward
        case .skipForward:      return Hicon.forward
        case .rewind15:         return Hicon.backward10Seconds
        case .forward15:        return Hicon.forward10Seconds
        case .xmarkCircle:      return Hicon.closeCircle
        case .playCircleFill:   return Hicon.playCircle
        case .gridSquare:       return Hicon.category
        
        // Symbols
        case .checkmark:        return Hicon.tick
        case .shrinkScreen:     return Hicon.zoomOut
        case .expandScreen:     return Hicon.zoomIn
        case .headphones:       return Hicon.headphone1
        case .heartSlash:       return Hicon.dislike
        case .personCircle:     return Hicon.profileCircle
        case .album:            return Hicon.record
        case .infoCircle:       return Hicon.informationCircle
        case .arrowDownCircle:  return Hicon.downCircle1
        case .sun:              return Hicon.sun1
        case .moon:             return Hicon.moon
        case .halfCircle:       return Hicon.sun2
        
        // Settings Icons
        case .equalizer:        return Hicon.setting
        // 沉浸模式改用电视/影院图标（原为 zoomIn 放大镜样式）
        case .immersive:        return Hicon.tv
        case .playerTheme:      return Hicon.palette
        
        // Podcast Categories
        case .catMusic:         return Hicon.music
        case .catLife:          return Hicon.discovery2
        case .catEmotion:       return Hicon.heart1
        case .catCreate:        return Hicon.pen
        case .catAcg:           return Hicon.ps51
        case .catEntertain:     return Hicon.tv
        case .catTalkshow:      return Hicon.microphone1
        case .catBook:          return Hicon.bookmark1
        case .catKnowledge:     return Hicon.education
        case .catBusiness:      return Hicon.work
        case .catHistory:       return Hicon.timeCircle1
        case .catNews:          return Hicon.documentAlignLeft1
        case .catParenting:     return Hicon.happy1
        case .catTravel:        return Hicon.location
        case .catCrosstalk:     return Hicon.microphone2
        case .catFood:          return Hicon.cupOfTea
        case .catTech:          return Hicon.display1
        case .catDefault:       return Hicon.folder1
        case .catPodcast:       return Hicon.radio
        case .catElectronic:    return Hicon.activity2
        case .catStar:          return Hicon.star1
        case .catDrama:         return Hicon.video1
        case .catStory:         return Hicon.bookmark2
        case .catOther:         return Hicon.moreCircle
        case .catPublish:       return Hicon.documentAlignLeft5
        
        // Emoji & Debug
        case .emoji:            return Hicon.happy1
        case .share:            return Hicon.send2
        case .logInfo:          return Hicon.informationCircle
        case .logDebug:         return Hicon.faqCircle
        case .logError:         return Hicon.dangerCircle
        case .logNetwork:       return Hicon.wifi
        case .logSuccess:       return Hicon.tickCircle
        case .arrowDownToLine:  return Hicon.download
        
        // Filters & Misc
        case .filter:           return Hicon.filter1
        case .microphone:       return Hicon.microphone1
        case .fmMode:           return Hicon.radio
        case .audioWave:        return Hicon.voiceShape2
        
        case .mv:               return Hicon.video1
        
        case .hitokoto:         return Hicon.message1
        
        // Bar Styles
        case .layers:           return Hicon.category
        case .tabBar:           return Hicon.menuHamburger
        case .minimalBar:       return Hicon.minus
        case .floatingBall:     return Hicon.record
        }
    }
}

extension AppInterfaceIconSet {
    func image(
        for icon: MonoIcon.IconType,
        prefersLightOutline: Bool = UITraitCollection.current.userInterfaceStyle == .dark
    ) -> UIImage {
        switch self {
        case .hicon:
            return icon.hiconImage
        case .sfSymbols:
            return icon.sfSymbolImage
        case .zappicon:
            return icon.zappiconImage(style: AppInterfaceIconSet.selectedZappiconStyle)
        case .lucide:
            return icon.lucideImage
        case .solar:
            return icon.solarImage(style: AppInterfaceIconSet.selectedSolarStyle)
        case .blobIcons:
            return icon.blobIconImage
        case .doodlePop:
            return icon.doodlePopImage(prefersLightOutline: prefersLightOutline)
        case .pawPrint:
            return icon.pawPrintImage(prefersLightOutline: prefersLightOutline)
        case .dotDogSnake:
            return icon.dotDogSnakeImage(prefersLightOutline: prefersLightOutline)
        case .minimalWhiteIcons:
            return icon.minimalWhiteIconImage(prefersLightOutline: prefersLightOutline)
        case .pulseBloom:
            return icon.pulseBloomImage(prefersLightOutline: prefersLightOutline)
        case .monoGlyph:
            return icon.monoGlyphImage(prefersLightOutline: prefersLightOutline)
        }
    }
}

// MARK: - IconType → SF Symbols Mapping

extension MonoIcon.IconType {
    /// SF Symbols 图标包：全部映射到系统符号，按模板着色渲染。
    /// 个别新符号在旧系统不可用时回退到 Hicon 同名图标，保证永不缺图。
    var sfSymbolImage: UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .medium)
        for name in sfSymbolNames {
            if let image = UIImage(systemName: name, withConfiguration: configuration) {
                return image
            }
        }
        return hiconImage
    }

    /// 首选符号在前，兼容回退在后
    private var sfSymbolNames: [String] {
        switch self {
        // Tab Bar / Navigation
        case .home:             return ["house"]
        case .homeFilled:       return ["house.fill"]
        case .podcast:          return ["mic"]
        case .podcastFilled:    return ["mic.fill"]
        case .library:          return ["square.stack"]
        case .libraryFilled:    return ["square.stack.fill"]
        case .search:           return ["magnifyingglass"]
        case .profile:          return ["person"]
        case .profileFilled:    return ["person.fill"]

        // Playback Controls
        case .play:             return ["play.fill"]
        case .pause:            return ["pause.fill"]
        case .next:             return ["forward.fill"]
        case .previous:         return ["backward.fill"]
        case .stop:             return ["stop.fill"]
        case .repeatMode:       return ["repeat"]
        case .repeatOne:        return ["repeat.1"]
        case .shuffle:          return ["shuffle"]
        case .refresh:          return ["arrow.clockwise"]

        // Actions
        case .like:             return ["heart"]
        case .liked:            return ["heart.fill"]
        case .list:             return ["line.3.horizontal"]
        case .back:             return ["chevron.left"]
        case .more:             return ["ellipsis"]
        case .close:            return ["xmark"]
        case .trash:            return ["trash"]
        case .fm:               return ["radio"]
        case .bell:             return ["bell"]

        // Settings & Utility
        case .settings:         return ["gearshape"]
        case .download:         return ["arrow.down.circle"]
        case .cloud:            return ["icloud"]
        case .chevronRight:     return ["chevron.right"]
        case .chevronLeft:      return ["chevron.left"]
        case .chevronDown:      return ["chevron.down"]
        case .chevronUp:        return ["chevron.up"]
        case .magnifyingGlass:  return ["magnifyingglass"]
        case .xmark:            return ["xmark"]
        case .fullscreen:       return ["arrow.up.left.and.arrow.down.right"]
        case .sparkle:          return ["sparkles"]
        case .soundQuality:     return ["waveform"]
        case .storage:          return ["internaldrive"]
        case .haptic:           return ["iphone.radiowaves.left.and.right", "waveform.path"]
        case .info:             return ["info.circle"]

        // Media Info
        case .clock:            return ["clock"]
        case .musicNoteList:    return ["music.note.list"]
        case .chart:            return ["chart.bar"]
        case .translate:        return ["textformat"]
        case .karaoke:          return ["music.mic"]
        case .lock:             return ["lock"]
        case .unlock:           return ["lock.open"]
        case .qr:               return ["qrcode.viewfinder"]
        case .phone:            return ["phone"]
        case .send:             return ["paperplane"]
        case .musicNote:        return ["music.note"]
        case .save:             return ["bookmark"]

        // Player
        case .playerDownload:   return ["arrow.down.to.line"]
        case .comment:          return ["bubble.left"]

        // Library
        case .history:          return ["clock.arrow.circlepath"]
        case .playCircle:       return ["play.circle"]
        case .warning:          return ["exclamationmark.triangle"]
        case .personEmpty:      return ["person.crop.circle.badge.questionmark"]
        case .playNext:         return ["text.line.first.and.arrowtriangle.forward", "text.insert"]
        case .add:              return ["plus"]
        case .addToQueue:       return ["text.badge.plus"]

        // Podcast
        case .radio:            return ["radio"]
        case .micSlash:         return ["mic.slash"]
        case .waveform:         return ["waveform"]
        case .skipBack:         return ["backward.end"]
        case .skipForward:      return ["forward.end"]
        case .rewind15:         return ["gobackward.15"]
        case .forward15:        return ["goforward.15"]
        case .xmarkCircle:      return ["xmark.circle"]
        case .playCircleFill:   return ["play.circle.fill"]
        case .gridSquare:       return ["square.grid.2x2"]

        // Symbols
        case .checkmark:        return ["checkmark"]
        case .shrinkScreen:     return ["arrow.down.right.and.arrow.up.left"]
        case .expandScreen:     return ["arrow.up.left.and.arrow.down.right"]
        case .headphones:       return ["headphones"]
        case .heartSlash:       return ["heart.slash"]
        case .personCircle:     return ["person.circle"]
        case .album:            return ["opticaldisc"]
        case .infoCircle:       return ["info.circle"]
        case .arrowDownCircle:  return ["arrow.down.circle"]
        case .sun:              return ["sun.max"]
        case .moon:             return ["moon"]
        case .halfCircle:       return ["circle.lefthalf.filled", "circle.lefthalf.fill"]

        // Settings Icons
        case .equalizer:        return ["slider.horizontal.3"]
        case .immersive:        return ["play.tv"]
        case .playerTheme:      return ["paintpalette"]

        // Podcast Categories
        case .catMusic:         return ["music.note"]
        case .catLife:          return ["leaf"]
        case .catEmotion:       return ["heart"]
        case .catCreate:        return ["pencil.and.outline"]
        case .catAcg:           return ["gamecontroller"]
        case .catEntertain:     return ["tv"]
        case .catTalkshow:      return ["mic"]
        case .catBook:          return ["book"]
        case .catKnowledge:     return ["graduationcap"]
        case .catBusiness:      return ["briefcase"]
        case .catHistory:       return ["building.columns"]
        case .catNews:          return ["newspaper"]
        case .catParenting:     return ["face.smiling"]
        case .catTravel:        return ["map"]
        case .catCrosstalk:     return ["person.2.wave.2"]
        case .catFood:          return ["cup.and.saucer"]
        case .catTech:          return ["desktopcomputer"]
        case .catDefault:       return ["folder"]
        case .catPodcast:       return ["dot.radiowaves.left.and.right"]
        case .catElectronic:    return ["waveform.path"]
        case .catStar:          return ["star"]
        case .catDrama:         return ["theatermasks"]
        case .catStory:         return ["text.book.closed"]
        case .catOther:         return ["ellipsis.circle"]
        case .catPublish:       return ["doc.text"]

        // Emoji & Debug
        case .emoji:            return ["face.smiling"]
        case .share:            return ["square.and.arrow.up"]
        case .logInfo:          return ["info.circle"]
        case .logDebug:         return ["ladybug"]
        case .logError:         return ["exclamationmark.octagon"]
        case .logNetwork:       return ["wifi"]
        case .logSuccess:       return ["checkmark.circle"]
        case .arrowDownToLine:  return ["arrow.down.to.line"]

        // Filters & Misc
        case .filter:           return ["line.3.horizontal.decrease"]
        case .microphone:       return ["mic"]
        case .fmMode:           return ["radio"]
        case .audioWave:        return ["waveform.path"]

        case .mv:               return ["play.rectangle"]
        case .layers:           return ["square.3.layers.3d", "square.stack.3d.up"]
        case .hitokoto:         return ["quote.bubble"]
        case .tabBar:           return ["rectangle.bottomthird.inset.filled", "dock.rectangle"]
        case .minimalBar:       return ["minus"]
        case .floatingBall:     return ["circle.circle"]
        }
    }
}

// MARK: - IconType → Bitmap Icon Mapping

extension MonoIcon.IconType {
    /// 位图图标包的资源 id。
    /// 沉浸模式改用「mv」视频图标（各包原有的 immersive 资源为放大箭头样式，与当前沉浸模式含义不符）。
    private var bitmapIconId: String {
        switch self {
        case .immersive: return "mv"
        default: return String(describing: self)
        }
    }

    var blobIconImage: UIImage {
        UIImage(blobIconId: bitmapIconId) ?? hiconImage
    }

    var doodlePopImage: UIImage {
        UIImage(doodlePopIconId: bitmapIconId) ?? hiconImage
    }

    func doodlePopImage(prefersLightOutline: Bool) -> UIImage {
        let image = doodlePopImage
        let style: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light
        return UIImage(doodlePopIconId: bitmapIconId, userInterfaceStyle: style) ?? image
    }

    var pawPrintImage: UIImage {
        UIImage(pawPrintIconId: bitmapIconId) ?? hiconImage
    }

    func pawPrintImage(prefersLightOutline: Bool) -> UIImage {
        let image = pawPrintImage
        let style: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light
        return UIImage(pawPrintIconId: bitmapIconId, userInterfaceStyle: style) ?? image
    }

    var dotDogSnakeImage: UIImage {
        UIImage(dotDogSnakeIconId: bitmapIconId) ?? hiconImage
    }

    func dotDogSnakeImage(prefersLightOutline: Bool) -> UIImage {
        let image = dotDogSnakeImage
        let style: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light
        return UIImage(dotDogSnakeIconId: bitmapIconId, userInterfaceStyle: style) ?? image
    }

    var minimalWhiteIconImage: UIImage {
        UIImage(minimalWhiteIconId: bitmapIconId) ?? hiconImage
    }

    func minimalWhiteIconImage(prefersLightOutline: Bool) -> UIImage {
        let image = minimalWhiteIconImage
        let style: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light
        return UIImage(minimalWhiteIconId: bitmapIconId, userInterfaceStyle: style) ?? image
    }

    var pulseBloomImage: UIImage {
        // Keep the compatibility accessor deterministic. Tab surfaces use the
        // explicit variant overload below instead of a trait-adaptive image.
        UIImage(pulseBloomIconId: bitmapIconId, userInterfaceStyle: .light) ?? hiconImage
    }

    func pulseBloomImage(prefersLightOutline: Bool) -> UIImage {
        pulseBloomImage(assetId: nil, prefersLightOutline: prefersLightOutline)
    }

    func pulseBloomImage(assetId: String?, prefersLightOutline: Bool) -> UIImage {
        let resolvedAssetId = assetId ?? bitmapIconId
        let requestedStyle: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light

        return UIImage(
            pulseBloomIconId: resolvedAssetId,
            userInterfaceStyle: requestedStyle
        ) ?? UIImage(
            pulseBloomIconId: resolvedAssetId,
            userInterfaceStyle: .light
        ) ?? UIImage(
            pulseBloomIconId: bitmapIconId,
            userInterfaceStyle: requestedStyle
        ) ?? hiconImage
    }

    var monoGlyphImage: UIImage {
        monoGlyphImage(prefersLightOutline: false)
    }

    func monoGlyphImage(prefersLightOutline: Bool) -> UIImage {
        monoGlyphImage(
            assetId: nil,
            prefersLightOutline: prefersLightOutline,
            style: AppInterfaceIconSet.selectedMonoGlyphStyle
        )
    }

    func monoGlyphImage(assetId: String?, prefersLightOutline: Bool, style: MonoGlyphIconStyle) -> UIImage {
        let resolvedAssetId = assetId ?? bitmapIconId
        let requestedStyle: UIUserInterfaceStyle = prefersLightOutline ? .dark : .light

        return UIImage(
            monoGlyphIconId: resolvedAssetId,
            userInterfaceStyle: requestedStyle,
            style: style
        ) ?? UIImage(
            monoGlyphIconId: bitmapIconId,
            userInterfaceStyle: requestedStyle,
            style: style
        ) ?? hiconImage
    }

}

#if os(iOS)
extension UIImage {
    static func monoSymbol(named name: String) -> UIImage {
        let icon = MonoIcon.IconType.fromSystemName(name).icon
        let iconSet = AppInterfaceIconSet.selectedFromDefaults
        let renderingMode: UIImage.RenderingMode = iconSet.usesOriginalArtwork ? .alwaysOriginal : .alwaysTemplate
        return iconSet.image(for: icon).withRenderingMode(renderingMode)
    }
}
#endif

// MARK: - IconType → Zappicon Mapping

extension MonoIcon.IconType {
    /// Zappicon (H173) 图标映射 — 根据用户选择的风格动态加载
    func zappiconImage(style: ZappiconIconStyle) -> UIImage {
        let name: String
        switch self {
        // Tab Bar / Navigation
        case .home:             name = "house"
        case .homeFilled:       name = "house-simple"
        case .podcast:          name = "microphone-stand"
        case .podcastFilled:    name = "microphone-stand"
        case .library:          name = "headphones"
        case .libraryFilled:    name = "headphones"
        case .search:           name = "search"
        case .profile:          name = "user"
        case .profileFilled:    name = "user-circle"

        // Playback Controls
        case .play:             name = "play"
        case .pause:            name = "pause"
        case .next:             name = "forward-step"
        case .previous:         name = "backward-step"
        case .stop:             name = "stop"
        case .repeatMode:       name = "repeat"
        case .repeatOne:        name = "repeat-1"
        case .shuffle:          name = "shuffle"
        case .refresh:          name = "arrows-rotate"

        // Actions
        case .like:             name = "heart"
        case .liked:            name = "heart"
        case .list:             name = "playlist"
        case .back:             name = "angle-left"
        case .more:             name = "menu-bars"
        case .close:            name = "xmark"
        case .trash:            name = "trash"
        case .fm:               name = "radio"
        case .bell:             name = "bell"

        // Settings & Utility
        case .settings:         name = "gear"
        case .download:         name = "download-arrow-down"
        case .cloud:            name = "cloud-upload"
        case .chevronRight:     name = "angle-right"
        case .chevronLeft:      name = "angle-left"
        case .chevronDown:      name = "angle-down"
        case .chevronUp:        name = "angle-up"
        case .magnifyingGlass:  name = "search"
        case .xmark:            name = "xmark"
        case .fullscreen:       name = "arrows-expand"
        case .sparkle:          name = "star"
        case .soundQuality:     name = "waveform-lines"
        case .storage:          name = "folder"
        case .haptic:           name = "waveform"
        case .info:             name = "info-circle"

        // Media Info
        case .clock:            name = "clock"
        case .musicNoteList:    name = "music-list"
        case .chart:            name = "music-list-wave"
        case .translate:        name = "newspaper"
        case .karaoke:          name = "microphone"
        case .lock:             name = "lock"
        case .unlock:           name = "unlock"
        case .qr:               name = "qr-code"
        case .phone:            name = "phone"
        case .send:             name = "send"
        case .musicNote:        name = "music-note"
        case .save:             name = "bookmark"

        // Player
        case .playerDownload:   name = "download-arrow-down"
        case .comment:          name = "comment-smile"

        // Library
        case .history:          name = "time-history"
        case .playCircle:       name = "play-circle"
        case .warning:          name = "exclamation-triangle"
        case .personEmpty:      name = "user"
        case .playNext:         name = "playlist-plus"
        case .add:              name = "plus"
        case .addToQueue:       name = "playlist-plus"

        // Podcast
        case .radio:            name = "radio"
        case .micSlash:         name = "microphone-slash"
        case .waveform:         name = "waveform"
        case .skipBack:         name = "backward"
        case .skipForward:      name = "forward"
        case .rewind15:         name = "time-past-15"
        case .forward15:        name = "time-next-15"
        case .xmarkCircle:      name = "xmark-circle"
        case .playCircleFill:   name = "play-circle"
        case .gridSquare:       name = "grid-square"

        // Symbols
        case .checkmark:        name = "check"
        case .shrinkScreen:     name = "arrows-compress"
        case .expandScreen:     name = "arrows-expand"
        case .headphones:       name = "headphones"
        case .heartSlash:       name = "heart-slash"
        case .personCircle:     name = "user-circle"
        case .album:            name = "music-note-circle"
        case .infoCircle:       name = "info-circle"
        case .arrowDownCircle:  name = "arrow-down-circle"
        case .sun:              name = "sun"
        case .moon:             name = "moon"
        case .halfCircle:       name = "sun"

        // Settings Icons
        case .equalizer:        name = "gear"
        // 沉浸模式改用电视/影院图标（原为 arrows-expand）
        case .immersive:        name = "tv"
        case .playerTheme:      name = "palette"

        // Podcast Categories
        case .catMusic:         name = "music"
        case .catLife:          name = "compass"
        case .catEmotion:       name = "heart"
        case .catCreate:        name = "pen"
        case .catAcg:           name = "game-controller"
        case .catEntertain:     name = "tv"
        case .catTalkshow:      name = "microphone"
        case .catBook:          name = "book"
        case .catKnowledge:     name = "diploma"
        case .catBusiness:      name = "briefcase"
        case .catHistory:       name = "clock"
        case .catNews:          name = "newspaper"
        case .catParenting:     name = "comment-smile"
        case .catTravel:        name = "location-arrow"
        case .catCrosstalk:     name = "microphone"
        case .catFood:          name = "mug-saucer"
        case .catTech:          name = "display"
        case .catDefault:       name = "folder"
        case .catPodcast:       name = "radio"
        case .catElectronic:    name = "waveform"
        case .catStar:          name = "star"
        case .catDrama:         name = "video"
        case .catStory:         name = "book"
        case .catOther:         name = "grid-circle"
        case .catPublish:       name = "send"

        // Emoji & Debug
        case .emoji:            name = "comment-smile"
        case .share:            name = "share"
        case .logInfo:          name = "info-circle"
        case .logDebug:         name = "search"
        case .logError:         name = "exclamation-triangle"
        case .logNetwork:       name = "wifi"
        case .logSuccess:       name = "check-circle"
        case .arrowDownToLine:  name = "download-arrow-down"

        // Filters & Misc
        case .filter:           name = "filter"
        case .microphone:       name = "microphone"
        case .fmMode:           name = "radio"
        case .audioWave:        name = "waveform-lines"
        case .mv:               name = "video"
        case .hitokoto:         name = "chat-dots"

        // Bar Styles
        case .layers:           name = "grid-square"
        case .tabBar:           name = "menu-bars"
        case .minimalBar:       name = "minus"
        case .floatingBall:     name = "record-audio"
        }

        // 拼接风格前缀加载：如 "light-play", "filled-heart"
        let assetName = "\(style.rawValue)-\(name)"
        return UIImage(zappiconId: assetName) ?? UIImage()
    }
}

// MARK: - IconType → Lucide Mapping

extension MonoIcon.IconType {
    /// Lucide 图标映射
    var lucideImage: UIImage {
        let name: String
        switch self {
        // Tab Bar / Navigation
        case .home:             name = "house"
        case .homeFilled:       name = "house"
        case .podcast:          name = "mic"
        case .podcastFilled:    name = "mic"
        case .library:          name = "headphones"
        case .libraryFilled:    name = "headphones"
        case .search:           name = "search"
        case .profile:          name = "user"
        case .profileFilled:    name = "circle-user"

        // Playback Controls
        case .play:             name = "play"
        case .pause:            name = "pause"
        case .next:             name = "skip-forward"
        case .previous:         name = "skip-back"
        case .stop:             name = "circle-stop"
        case .repeatMode:       name = "repeat"
        case .repeatOne:        name = "repeat-1"
        case .shuffle:          name = "shuffle"
        case .refresh:          name = "refresh-cw"

        // Actions
        case .like:             name = "heart"
        case .liked:            name = "heart"
        case .list:             name = "list-music"
        case .back:             name = "chevron-left"
        case .more:             name = "menu"
        case .close:            name = "x-line-top"
        case .trash:            name = "trash-2"
        case .fm:               name = "radio"
        case .bell:             name = "bell"

        // Settings & Utility
        case .settings:         name = "settings"
        case .download:         name = "download"
        case .cloud:            name = "cloud-upload"
        case .chevronRight:     name = "chevron-right"
        case .chevronLeft:      name = "chevron-left"
        case .chevronDown:      name = "chevron-down"
        case .chevronUp:        name = "chevron-up"
        case .magnifyingGlass:  name = "search"
        case .xmark:            name = "x-line-top"
        case .fullscreen:       name = "maximize-2"
        case .sparkle:          name = "star"
        case .soundQuality:     name = "music"
        case .storage:          name = "hard-drive-download"
        case .haptic:           name = "activity"
        case .info:             name = "info"

        // Media Info
        case .clock:            name = "clock"
        case .musicNoteList:    name = "list-music"
        case .chart:            name = "music-2"
        case .translate:        name = "book-open-text"
        case .karaoke:          name = "mic-vocal"
        case .lock:             name = "lock"
        case .unlock:           name = "lock-open"
        case .qr:               name = "scan-search"
        case .phone:            name = "phone"
        case .send:             name = "send"
        case .musicNote:        name = "music"
        case .save:             name = "bookmark"

        // Player
        case .playerDownload:   name = "download"
        case .comment:          name = "message-circle"

        // Library
        case .history:          name = "clock"
        case .playCircle:       name = "circle-play"
        case .warning:          name = "circle-alert"
        case .personEmpty:      name = "user"
        case .playNext:         name = "list-plus"
        case .add:              name = "plus"
        case .addToQueue:       name = "list-plus"

        // Podcast
        case .radio:            name = "radio"
        case .micSlash:         name = "mic-off"
        case .waveform:         name = "activity"
        case .skipBack:         name = "skip-back"
        case .skipForward:      name = "skip-forward"
        case .rewind15:         name = "skip-back"
        case .forward15:        name = "skip-forward"
        case .xmarkCircle:      name = "circle-x"
        case .playCircleFill:   name = "circle-play"
        case .gridSquare:       name = "grid-2x2"

        // Symbols
        case .checkmark:        name = "check"
        case .shrinkScreen:     name = "minimize-2"
        case .expandScreen:     name = "maximize-2"
        case .headphones:       name = "headphones"
        case .heartSlash:       name = "heart-off"
        case .personCircle:     name = "circle-user"
        case .album:            name = "disc-3"
        case .infoCircle:       name = "info"
        case .arrowDownCircle:  name = "circle-arrow-down"
        case .sun:              name = "sun"
        case .moon:             name = "moon"
        case .halfCircle:       name = "sun-moon"

        // Settings Icons
        case .equalizer:        name = "settings-2"
        // 沉浸模式改用「电视 + 播放」图标（原为 maximize-2）
        case .immersive:        name = "tv-minimal-play"
        case .playerTheme:      name = "palette"

        // Podcast Categories
        case .catMusic:         name = "music"
        case .catLife:          name = "heart-pulse"
        case .catEmotion:       name = "heart"
        case .catCreate:        name = "pen"
        case .catAcg:           name = "disc-2"
        case .catEntertain:     name = "tv"
        case .catTalkshow:      name = "mic"
        case .catBook:          name = "book-open"
        case .catKnowledge:     name = "book-check"
        case .catBusiness:      name = "briefcase"
        case .catHistory:       name = "clock"
        case .catNews:          name = "megaphone"
        case .catParenting:     name = "smile-plus"
        case .catTravel:        name = "map-pin-check"
        case .catCrosstalk:     name = "mic-vocal"
        case .catFood:          name = "concierge-bell"
        case .catTech:          name = "monitor-smartphone"
        case .catDefault:       name = "folder"
        case .catPodcast:       name = "radio"
        case .catElectronic:    name = "activity"
        case .catStar:          name = "star"
        case .catDrama:         name = "tv"
        case .catStory:         name = "book-open"
        case .catOther:         name = "circle-ellipsis"
        case .catPublish:       name = "send"

        // Emoji & Debug
        case .emoji:            name = "smile-plus"
        case .share:            name = "share-2"
        case .logInfo:          name = "info"
        case .logDebug:         name = "search"
        case .logError:         name = "circle-alert"
        case .logNetwork:       name = "wifi-pen"
        case .logSuccess:       name = "circle-check"
        case .arrowDownToLine:  name = "arrow-down-to-line"

        // Filters & Misc
        case .filter:           name = "list-filter"
        case .microphone:       name = "mic"
        case .fmMode:           name = "radio"
        case .audioWave:        name = "music-3"
        case .mv:               name = "video"
        case .hitokoto:         name = "message-circle"

        // Bar Styles
        case .layers:           name = "grid-2x2"
        case .tabBar:           name = "menu"
        case .minimalBar:       name = "minus"
        case .floatingBall:     name = "circle"
        }

        return UIImage(lucideId: name) ?? UIImage()
    }
}

// MARK: - IconType → Solar Mapping

extension MonoIcon.IconType {
    /// Solar Icons 图标映射 — 根据用户选择的风格动态加载
    func solarImage(style: SolarIconStyle) -> UIImage {
        let name: String
        switch self {
        case .home:             name = "home"
        case .homeFilled:       name = "home-2"
        case .podcast:          name = "microphone"
        case .podcastFilled:    name = "microphone"
        case .library:          name = "headphone"
        case .libraryFilled:    name = "headphone"
        case .search:           name = "search"
        case .profile:          name = "user"
        case .profileFilled:    name = "user-circle"
        case .play:             name = "play"
        case .pause:            name = "pause"
        case .next:             name = "fast-forward"
        case .previous:         name = "fast-backward"
        case .stop:             name = "pause-circle"
        case .repeatMode:       name = "sync"
        case .repeatOne:        name = "arrow-rotate-right"
        case .shuffle:          name = "shuffle"
        case .refresh:          name = "arrow-rotate-right"
        case .like:             name = "heart"
        case .liked:            name = "heart"
        case .list:             name = "list-ui"
        case .back:             name = "angle-left"
        case .more:             name = "3-dots-horizontal"
        case .close:            name = "cancel"
        case .trash:            name = "trash"
        case .fm:               name = "radio"
        case .bell:             name = "bell"
        case .settings:         name = "gear"
        case .download:         name = "download"
        case .cloud:            name = "cloud"
        case .chevronRight:     name = "angle-right"
        case .chevronLeft:      name = "angle-left"
        case .chevronDown:      name = "angle-down"
        case .chevronUp:        name = "angle-up"
        case .magnifyingGlass:  name = "search"
        case .xmark:            name = "cancel"
        case .fullscreen:       name = "expand"
        case .sparkle:          name = "star"
        case .soundQuality:     name = "music-2"
        case .storage:          name = "folder"
        case .haptic:           name = "activity"
        case .info:             name = "info-circle"
        case .clock:            name = "clock"
        case .musicNoteList:    name = "music"
        case .chart:            name = "music-2"
        case .translate:        name = "book-open"
        case .karaoke:          name = "microphone"
        case .lock:             name = "lock"
        case .unlock:           name = "lock-open"
        case .qr:               name = "grid-square"
        case .phone:            name = "phone"
        case .send:             name = "send"
        case .musicNote:        name = "music"
        case .save:             name = "bookmark"
        case .playerDownload:   name = "download"
        case .comment:          name = "comment-dots"
        case .history:          name = "clock"
        case .playCircle:       name = "play-circle"
        case .warning:          name = "info-circle"
        case .personEmpty:      name = "user"
        case .playNext:         name = "forward-circle"
        case .add:              name = "plus"
        case .addToQueue:       name = "forward-circle"
        case .radio:            name = "radio"
        case .micSlash:         name = "microphone"
        case .waveform:         name = "activity"
        case .skipBack:         name = "fast-backward"
        case .skipForward:      name = "fast-forward"
        case .rewind15:         name = "fast-backward"
        case .forward15:        name = "fast-forward"
        case .xmarkCircle:      name = "cancel-circle"
        case .playCircleFill:   name = "play-circle"
        case .gridSquare:       name = "grid-square"
        case .checkmark:        name = "check"
        case .shrinkScreen:     name = "compress"
        case .expandScreen:     name = "expand"
        case .headphones:       name = "headphone"
        case .heartSlash:       name = "heart"
        case .personCircle:     name = "user-circle"
        case .album:            name = "music-2"
        case .infoCircle:       name = "info-circle"
        case .arrowDownCircle:  name = "arrow-down-circle"
        case .sun:              name = "moon"
        case .moon:             name = "moon"
        case .halfCircle:       name = "moon"
        case .equalizer:        name = "gear"
        // 沉浸模式改用电视/影院图标（原为 expand）
        case .immersive:        name = "tv"
        case .playerTheme:      name = "color-palette"
        case .catMusic:         name = "music"
        case .catLife:          name = "compass"
        case .catEmotion:       name = "heart"
        case .catCreate:        name = "pen"
        case .catAcg:           name = "gamepad"
        case .catEntertain:     name = "tv"
        case .catTalkshow:      name = "microphone"
        case .catBook:          name = "book"
        case .catKnowledge:     name = "book-open"
        case .catBusiness:      name = "gear"
        case .catHistory:       name = "clock"
        case .catNews:          name = "megaphone"
        case .catParenting:     name = "heart"
        case .catTravel:        name = "location-pin"
        case .catCrosstalk:     name = "microphone"
        case .catFood:          name = "coffee-cup"
        case .catTech:          name = "tv"
        case .catDefault:       name = "folder"
        case .catPodcast:       name = "radio"
        case .catElectronic:    name = "activity"
        case .catStar:          name = "star"
        case .catDrama:         name = "tv"
        case .catStory:         name = "book"
        case .catOther:         name = "grid-circle"
        case .catPublish:       name = "send"
        case .emoji:            name = "heart"
        case .share:            name = "share-ios"
        case .logInfo:          name = "info-circle"
        case .logDebug:         name = "search"
        case .logError:         name = "cancel-circle"
        case .logNetwork:       name = "wifi"
        case .logSuccess:       name = "check-circle"
        case .arrowDownToLine:  name = "download"
        case .filter:           name = "filter"
        case .microphone:       name = "microphone"
        case .fmMode:           name = "radio"
        case .audioWave:        name = "activity"
        case .mv:               name = "play-circle"
        case .hitokoto:         name = "comment-dots"
        case .layers:           name = "grid-square"
        case .tabBar:           name = "list-ui"
        case .minimalBar:       name = "minus"
        case .floatingBall:     name = "play-circle"
        }

        let assetName = "\(style.rawValue)-\(name)"
        return UIImage(solarId: assetName) ?? UIImage()
    }
}
