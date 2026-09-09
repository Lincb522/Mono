// Widget Extension 入口

import WidgetKit
import SwiftUI

/// 注册可选主题、固定主题与控制中心播放组件的 Widget 扩展入口。
@main
struct musicBundle: WidgetBundle {
    var body: some Widget {
        SelectableNowPlayingWidget()
        NowPlayingWidget(theme: .polaroid)
        NowPlayingWidget(theme: .vinyl)
        NowPlayingWidget(theme: .vinylDark)
        NowPlayingWidget(theme: .poster)
        NowPlayingWidget(theme: .magazine)
        NowPlayingWidget(theme: .aperture)
        NowPlayingWidget(theme: .pager)
        NowPlayingWidget(theme: .pagerLight)
        NowPlayingWidget(theme: .radio)
        NowPlayingWidget(theme: .dashboard)
        NowPlayingWidget(theme: .soundwave)
        NowPlayingWidget(theme: .typewriter)
        NowPlayingWidget(theme: .lyrics)
        NowPlayingWidget(theme: .lyricsDark)
        NowPlayingWidget(theme: .lyricsCover)
        if #available(iOS 18, *) {
            PlayPauseControlWidget()
            NextTrackControlWidget()
            GameModeControlWidget()
        }
    }
}
