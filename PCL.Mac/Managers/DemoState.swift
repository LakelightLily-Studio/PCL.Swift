//
//  DemoState.swift
//  PCL.Mac
//
//  demo 分支专用：给演示场景提供快捷键所需的共享状态。
//  合回 main 之前应当连同 AppDelegate 里的按键处理一起删掉。
//

import SwiftUI
import Core

/// 演示用的共享状态。
final class DemoState: ObservableObject {
    static let shared: DemoState = .init()

    /// 每次自增都会让 `ContentView` 重建视图树，从而重播卡片进入动画。
    @Published private(set) var replayToken: Int = 0

    private init() {}

    /// 重播启动时的卡片进入动画。
    func replayEntryAnimation() {
        replayToken &+= 1
        log("演示：重播进入动画")
    }

    /// 数字键 1–4 对应的根页面。
    ///
    /// 只覆盖顶栏上恒定存在的四个按钮；联机页由功能开关控制，开关关闭时按钮
    /// 本身就不在，开关打开时它插在「设置」之前，所以不占用数字键，免得同一
    /// 个数字在不同开关状态下跳到不同页面。
    static let rootPages: [AppRoute] = [.launch, .download, .settings, .more]

    /// 数字键 1–4 的 `keyCode`，顺序即上表下标。
    static let digitKeyCodes: [UInt16] = [18, 19, 20, 21]

    /// 切换到顶栏第 `index` 个按钮对应的页面。
    @MainActor
    func openRootPage(at index: Int) {
        guard Self.rootPages.indices.contains(index) else { return }
        AppRouter.shared.setRoot(Self.rootPages[index])
    }
}
