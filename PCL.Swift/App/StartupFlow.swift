//
//  StartupFlow.swift
//  PCL.Swift
//
//  首次启动的三段式流程：开场动画 → 设置向导 → 启动器主体。
//  三段共用同一个窗口（AppWindow），差异只是窗口尺寸：
//  动画阶段锁在 370×450，向导阶段起拉到 1000×550，之后不再改动。
//
//  这里刻意不给类型加 @MainActor 标注：SwiftUI 的回调与
//  applicationDidFinishLaunching 都在主线程，而 AppDelegate 本身并未标注
//  隔离，跨到主线程的延后动作用 Task { @MainActor in } 显式跳一次即可。
//  所有方法都只允许在主线程调用。
//

import SwiftUI
import Core

final class StartupFlow: ObservableObject {
    enum Stage: Hashable {
        /// 开场动画，窗口为动画画布尺寸。
        case onboarding
        /// 设置向导（当前为占位页面）。
        case wizard
        /// 启动器主体。
        case launcher
    }

    @Published private(set) var stage: Stage

    /// 窗口由 AppDelegate 创建后注入，用于在阶段切换时改变窗口尺寸。
    private weak var window: AppWindow?

    /// 从动画到向导的过渡时长：窗口先长开，再淡入向导。
    private static let windowGrowDelay: Double = 0.2

    init(stage: Stage) {
        self.stage = stage
    }

    /// 依据配置推断本次启动应进入哪个阶段。
    static func initialStage() -> Stage {
        LauncherConfig.shared.hasCompletedOnboarding ? .launcher : .onboarding
    }

    func attach(window: AppWindow) {
        self.window = window
        window.applyStartupStage(stage, animated: false)
    }

    /// 开场动画点「继续」。窗口先拉到正常尺寸，向导随后淡入，
    /// 避免向导的内容在半大不小的窗口里重排一次。
    func continueFromOnboarding() {
        guard stage == .onboarding else { return }
        window?.applyStartupStage(.wizard, animated: true)
        Task { @MainActor in
            try? await Task.sleep(seconds: Self.windowGrowDelay)
            withAnimation(.easeInOut(duration: 0.28)) {
                self.stage = .wizard
            }
            log("开场动画结束，进入设置向导")
        }
    }

    /// 设置向导完成：落盘标记并切到启动器主体。
    func finishWizard() {
        guard stage == .wizard else { return }
        LauncherConfig.shared.hasCompletedOnboarding = true
        LauncherConfig.shared.hasEnteredLauncher = true
        window?.applyStartupStage(.launcher, animated: false)
        withAnimation(.easeInOut(duration: 0.25)) {
            stage = .launcher
        }
        log("设置向导完成，进入启动器")
        // 更新检查依赖 ContentView 里的弹窗层，等主体真正出现后再发起。
        Task { @MainActor in
            try? await Task.sleep(seconds: 0.6)
            UpdateService.shared.runInteractiveUpdateFlow()
        }
    }

    /// demo 分支用：把窗口缩回动画尺寸并重播整段开场。
    func restartOnboarding() {
        window?.applyStartupStage(.onboarding, animated: true)
        withAnimation(.easeInOut(duration: 0.2)) {
            stage = .onboarding
        }
    }
}
