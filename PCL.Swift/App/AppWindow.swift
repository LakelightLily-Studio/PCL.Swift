//
//  AppWindow.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/29.
//

import SwiftUI
import Core

fileprivate let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

class AppWindow: NSWindow, NSWindowDelegate {
    /// 开场动画的画布尺寸：与应用图标同源的小方窗。
    static let onboardingSize: NSSize = .init(width: 370, height: 450)
    /// 启动器主体的最小尺寸；向导与主体共用这一档。
    static let launcherMinSize: NSSize = .init(width: 1000, height: 550)
    /// 解除尺寸限制用的上界，等价于「不再限制」。
    private static let unboundedSize: NSSize = .init(width: 10_000, height: 10_000)
    /// 自定义标题栏的高度，与 `TitleBarView` 保持一致。
    static let titleBarHeight: CGFloat = 48
    /// 是否已经排了一次按钮对齐，用于合并 resize 期间的高频通知。
    private var isButtonsAlignmentScheduled: Bool = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init(instanceManager: InstanceManager, startupFlow: StartupFlow) {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 1000, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        
        self.standardWindowButton(.zoomButton)?.isHidden = true
        
        // 不把 NSHostingView 直接当 contentView：那样 SwiftUI 的「理想尺寸」会顶穿
        // 窗口（向导里的 ScrollView 理想高度没有上限，实测会把窗口撑到 1361pt）。
        // 套一层普通 NSView，让窗口尺寸只由启动阶段决定，SwiftUI 只负责填满。
        let hostingView: NSHostingView<RootView> = .init(rootView: RootView(instanceManager: instanceManager, startupFlow: startupFlow))
        hostingView.autoresizingMask = [.width, .height]
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }

        let container: NSView = NSView(frame: .init(origin: .zero, size: Self.launcherMinSize))
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        self.contentView = container
        self.delegate = self
        
        // 开场动画与向导共用这一扇窗口，尺寸由 StartupFlow 逐阶段调整；
        // 只有直接进入主体的会话才沿用上次的窗口位置与大小。
        if startupFlow.stage == .launcher {
            self.setFrameAutosaveName("AppWindow")
        }
        startupFlow.attach(window: self)
        self.center()
    }
    
    /// 按启动阶段调整窗口外壳。
    ///
    /// 动画阶段窗口不可缩放、隐藏三色按钮，避免用户手动拖出一个既不像动画画布
    /// 也不像启动器主体的中间尺寸；进入向导时再一次性放开。
    func applyStartupStage(_ stage: StartupFlow.Stage, animated: Bool) {
        switch stage {
        case .onboarding:
            setWindowButtonsHidden(true)
            styleMask.remove(.resizable)
            minSize = Self.onboardingSize
            maxSize = Self.onboardingSize
            resizeContent(to: Self.onboardingSize, animated: animated)
        case .wizard, .launcher:
            setWindowButtonsHidden(false)
            styleMask.insert(.resizable)
            minSize = Self.launcherMinSize
            maxSize = Self.unboundedSize
            // 向导阶段窗口要从动画尺寸长到主体尺寸；进入主体时尺寸已经就位，无需再动。
            if stage == .wizard {
                resizeContent(to: Self.launcherMinSize, animated: animated)
            }
        }
    }

    /// 以窗口中心为锚点改变内容尺寸：右下角不动、四周对称长开，
    /// 这样从动画画布长到启动器时视觉重心不会突然偏移。
    private func resizeContent(to size: NSSize, animated: Bool) {
        var frame: NSRect = self.frame
        let current: NSSize = contentRect(forFrameRect: frame).size
        let deltaWidth: CGFloat = size.width - current.width
        let deltaHeight: CGFloat = size.height - current.height
        guard abs(deltaWidth) > 0.5 || abs(deltaHeight) > 0.5 else { return }
        frame.size.width += deltaWidth
        frame.size.height += deltaHeight
        frame.origin.x -= deltaWidth / 2
        frame.origin.y -= deltaHeight / 2

        guard animated else {
            setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(frame, display: true)
        }
    }

    /// 只控制关闭与最小化按钮。
    ///
    /// 缩放（全屏）按钮始终隐藏：这个 App 的窗口尺寸由启动阶段决定，
    /// 放开全屏会让「动画画布 → 启动器」的尺寸过渡失去意义；
    /// 早先这里连 zoomButton 一起恢复，导致播完开场动画后全屏按钮又冒出来。
    private func setWindowButtonsHidden(_ hidden: Bool) {
        standardWindowButton(.closeButton)?.isHidden = hidden
        standardWindowButton(.miniaturizeButton)?.isHidden = hidden
        standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    /// 缩放按钮在任何阶段都不出现。
    ///
    /// `standardWindowButton(_:)` 的 `isHidden` 会被 AppKit 在窗口状态变化
    /// （尺寸动画、成为主窗口、全屏状态同步）时重新写回，所以除了切换阶段时
    /// 设一次，还要在 `windowDidUpdate` 里保持。
    private func refreshZoomButtonVisibility() {
        guard let zoom = standardWindowButton(.zoomButton), !zoom.isHidden else { return }
        zoom.isHidden = true
    }

    /// 把三色按钮摆到自定义标题栏的视觉重心。
    ///
    /// 透明标题栏（`titlebarAppearsTransparent` + `fullSizeContentView`）下，AppKit 按
    /// 标准 28pt 标题栏摆放按钮；本 App 的标题栏是 48pt，所以要自己摆。
    ///
    /// 关键点：**不要只挪按钮的父容器**。实测拖动改变窗口尺寸后，AppKit 会把容器
    /// 留在 (7, -10)、却把容器内的按钮重排到 (0, 16)——容器看起来「已就位」，
    /// 按钮却跑到了左上角。所以这里按绝对位置逐个摆放按钮自身。
    ///
    /// 目标几何：红点圆心距窗口左 20pt、垂直居中于 48pt 标题栏（即距顶 24pt）。
    private func alignWindowButtons() {
        guard let titlebarView = standardWindowButton(.closeButton)?.superview else {
            return
        }

        let buttons: [NSButton] = [.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { standardWindowButton($0) }
            .filter { !$0.isHidden }
        guard !buttons.isEmpty else { return }

        // 按钮直径（10pt 圆点在 14pt 的按钮框里），圆心距左边 20pt。
        let buttonSize: CGFloat = buttons[0].frame.size.width
        let spacing: CGFloat = 20
        let leading: CGFloat = 20 - buttonSize / 2
        // 容器高 28pt、按钮在容器内垂直居中；标题栏 48pt 时的容器原点 y。
        let containerHeight: CGFloat = titlebarView.frame.height
        let containerTop: CGFloat = (Self.titleBarHeight - containerHeight) / 2

        for (index, button) in buttons.enumerated() {
            let x: CGFloat = leading + CGFloat(index) * spacing
            // 容器内坐标：按钮在容器内垂直居中。
            let y: CGFloat = (containerHeight - button.frame.size.height) / 2
            let target = NSRect(x: x, y: y, width: button.frame.size.width, height: button.frame.size.height)
            if abs(button.frame.origin.x - target.origin.x) > 0.5 || abs(button.frame.origin.y - target.origin.y) > 0.5 {
                button.frame = target
            }
        }

        // 容器自身也要回到顶部，否则按钮的绝对位置仍会被容器带着跑。
        if abs(titlebarView.frame.origin.x) > 0.5 || abs(titlebarView.frame.origin.y + containerTop) > 0.5 {
            titlebarView.frame.origin = CGPoint(x: 0, y: -containerTop)
        }
    }

    /// 延后一拍再对齐：resize 过程中 AppKit 会在同一轮布局里再次改写容器 frame，
    /// 同步设置会被覆盖，必须等它排完。
    ///
    /// 拖动窗口边缘时 `windowDidResize` 每帧都会来，这里用一次性标记合并，
    /// 保证同一轮 runloop 只排一次对齐。
    private func scheduleWindowButtonsAlignment() {
        guard !isButtonsAlignmentScheduled else { return }
        isButtonsAlignmentScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isButtonsAlignmentScheduled = false
            self.alignWindowButtons()
        }
    }

    func windowDidUpdate(_ notification: Notification) {
        refreshZoomButtonVisibility()
        alignWindowButtons()
    }

    func windowDidResize(_ notification: Notification) {
        refreshZoomButtonVisibility()
        scheduleWindowButtonsAlignment()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        scheduleWindowButtonsAlignment()
    }
}
