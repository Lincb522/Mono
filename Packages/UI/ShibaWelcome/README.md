# 小柴犬欢迎动画 · SwiftUI

重设计版角色的 SwiftUI 实现。包含完整透明角色原画、Metal 连续形变、六个动作、欢迎页与示例入口。

Mono 接入副本：支持 iOS 16+ 或 macOS 13+。iOS 17+ / macOS 14+ 使用原始 Metal 形变动画；较早系统显示完整静态角色。没有第三方依赖，原始交付目录未修改。

## 接入现有项目

1. 解压后，在 Xcode 的包依赖界面将 `ShibaWelcomeSwiftUI` 目录作为本地 Swift Package 添加，选择 `ShibaWelcome` 产品并关联你的 App target。
2. 在需要使用的 Swift 文件中添加 `import ShibaWelcome`。
3. 放入角色组件，或直接使用完整欢迎页。

```swift
import SwiftUI
import ShibaWelcome

struct ContentView: View {
    @State private var replayToken = 0

    var body: some View {
        VStack(spacing: 20) {
            ShibaMascotView(action: .welcome, replayToken: replayToken)
                .frame(width: 280, height: 280)

            Button("重播") { replayToken += 1 }
        }
    }
}
```

完整欢迎页：

```swift
ShibaWelcomeScreen {
    // 在这里更新你的路由或首次启动状态。
}
```

要运行完整演示，新建 iOS SwiftUI App，添加本地包后，用 `Examples/ShibaWelcomeDemoApp.swift` 替换自动生成的 App 入口。App target 中只保留一个 `@main`。`Examples/MotionGallery.swift` 提供六个动作的 Xcode Preview。

## 动作和播放行为

| action | 动作 | 时长 |
| --- | --- | --- |
| .welcome | 探身 → 点头 → 歪头，穿插眨眼 | 4.6 秒 |
| .appear | 探身出现 | 2.4 秒 |
| .nod | 轻轻点头 | 2.6 秒 |
| .tilt | 好奇歪头 | 3.2 秒 |
| .blink | 温柔眨眼 | 2.6 秒 |
| .breathe | 一次呼吸 | 3.6 秒 |

- View 每次出现时播放一次；改变 `action` 或增加 `replayToken` 会从头播放。
- 播放结束停留在结束姿态，停止 TimelineView 的动画刷新，并调用可选的 `onCompletion`。Mono 用此回调衔接已有的首页准备与自动进入流程。静态模式在角色出现时通知完成。
- 进入后台或失去活动状态时暂停；回到前台从暂停时间继续，后台时间不计入动作。
- 开启“减少动态效果”时显示静态结束姿态；关闭后通过切换动作或重播再次播放。
- 欢迎页的“开始使用”随时可点，不需要等待动画结束。
- 动画请求最高 60 Hz 的时间线更新，实际帧率取决于设备和系统调度。

## 调整

`ShibaAction.swift`：动作时长、关键时间、角度和幅度。

`ShibaMascotView.swift`：时间线、生命周期、着色器参数、入场缩放和位移。

`Shaders/ShibaDeform.metal`：同一张角色原画的连续形变。SwiftUI 的 distortionEffect 返回目标像素对应的源坐标，因此这里对形变做数值反解。

`Resources/ShibaAssets.xcassets`：768 × 768 透明角色。头部、眼睛和尾巴的控制范围按这张图标定；替换不同构图的图片时，需要同步调整着色器中的位置。

建议显示宽度 240–320 pt，并保持正方形区域。将本地包完整保留在项目目录中，着色器通过包内 Bundle 加载。

## 验证情况

原始交付未经过 Apple 平台构建。Mono 接入的验证记录见仓库 `artifacts/welcome-shiba-integration/validation/`；完整 App 构建、着色器资源在 App 中的加载及真机效果仍需在 Xcode 中验证。包内附有播放时钟 XCTest，用于检查后台暂停、结束停帧和重播行为。

形变参数来自已交付的角色动画；另行检查了逆映射的数值收敛。此项检查不替代 Apple Metal 编译或设备上的性能测试。

## API 参考

- [SwiftUI distortionEffect](https://developer.apple.com/documentation/swiftui/view/distortioneffect(_:maxsampleoffset:isenabled:))
- [ShaderLibrary.bundle](https://developer.apple.com/documentation/swiftui/shaderlibrary/bundle(_:))
- [AnimationTimelineSchedule](https://developer.apple.com/documentation/swiftui/animationtimelineschedule/init(minimuminterval:paused:))
