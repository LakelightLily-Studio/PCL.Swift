//
//  DevTools.swift
//  PCL.Swift
//
//  开发期快捷键，只在 Debug 构建里存在。
//
//  编译条件 PCL_DEV_TOOLS 由 Configs/Debug.xcconfig 定义，Release.xcconfig 不定义，
//  因此整个文件在正式版里不参与编译——不是运行时藏入口，而是二进制里根本没有这段代码。
//  新增开发期能力请一并放进这个条件里，不要退化成运行时开关或功能开关：
//  那些会被正式版带上，还要额外维护「什么时候不该触发」的判断。
//

#if PCL_DEV_TOOLS

import AppKit
import Core

/// 开发期快捷键。仅 Debug 构建可见。
enum DevShortcuts {
    enum Shortcut {
        /// ⌘R：重播「开场动画 → 设置向导 → 启动器」整段流程。
        case replayOnboarding
        /// 数字键 1–4：切到顶栏第 n 个页面。
        case openRootPage(index: Int)
    }

    /// 数字键 1–4 对应的根页面，顺序与顶栏按钮一致。
    ///
    static let rootPages: [AppRoute] = [.launch, .download, .settings, .more]

    /// 数字键 1–4 的 keyCode（ANSI 键盘），顺序即 rootPages 的下标。
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21]

    /// 判断这次 keyDown 是否命中开发期快捷键。
    ///
    /// 只做事件层面的判断，不碰任何 App 状态：NSEvent 的本地监听闭包不是
    /// @MainActor 上下文，在这里读 AppRouter 会破坏隔离；真正的副作用由调用方
    /// 跳回主线程后交给 perform(_:startupFlow:)。
    static func shortcut(for event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "r" {
            return .replayOnboarding
        }
        if flags.isEmpty, let index = digitKeyCodes.firstIndex(of: event.keyCode) {
            return .openRootPage(index: index)
        }
        return nil
    }

    /// 执行快捷键。必须在主线程调用。
    @MainActor
    static func perform(_ shortcut: Shortcut, startupFlow: StartupFlow) {
        // 弹窗打开时不抢键盘：对话框自己要用 Esc / 回车。
        guard MessageBoxManager.shared.currentMessageBox == nil else { return }

        switch shortcut {
        case .replayOnboarding:
            replayOnboarding(startupFlow: startupFlow)
        case .openRootPage(let index):
            // 向导阶段没有顶栏，切页面没有意义；文本框正在编辑时数字键属于输入内容。
            guard startupFlow.stage == .launcher, !isEditingText else { return }
            openRootPage(at: index)
        }
    }

    /// 当前是否有文本框在编辑（搜索框、输入框）。
    @MainActor
    private static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    /// 把窗口缩回动画画布，重播整段引导流程。
    ///
    /// 不改 hasCompletedOnboarding：重播只是回看流程，中途退出下次仍直接进启动器；
    /// 走完向导时 StartupFlow.finishWizard() 会重新置 true，两种情况都不会丢配置。
    @MainActor
    private static func replayOnboarding(startupFlow: StartupFlow) {
        // 先回启动页：重播结束后回到启动器时，不会停在重播前的子页面上。
        AppRouter.shared.setRoot(.launch)
        startupFlow.restartOnboarding()
        log("开发工具：重播开场动画与设置向导")
    }

    /// 切到顶栏第 index 个按钮对应的页面。
    @MainActor
    private static func openRootPage(at index: Int) {
        guard rootPages.indices.contains(index) else { return }
        AppRouter.shared.setRoot(rootPages[index])
        log("开发工具：切换到\(rootPages[index].stringValue)")
    }
}

#endif
