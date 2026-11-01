//
//  RootView.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/4/16.
//

import SwiftUI
import Core

/// 窗口的唯一根视图。
///
/// 开场动画、设置向导、启动器主体都挂在这里，靠 `StartupFlow.stage` 切换：
/// 三者始终是同一个窗口，只有窗口尺寸随阶段变化（见 `AppWindow.applyStartupStage`）。
///
/// 消息框与提示条挂在这一层而不是 `ContentView` 里：向导要弹正版账号的设备码，
/// 那一阶段 `ContentView` 还不存在，挂在里面会静默丢消息。
struct RootView: View {
    @ObservedObject var instanceManager: InstanceManager
    @ObservedObject var startupFlow: StartupFlow

    var body: some View {
        ZStack {
            switch startupFlow.stage {
            case .onboarding:
                StartupOnboardingView {
                    startupFlow.continueFromOnboarding()
                }
                .transition(.opacity)
            case .wizard:
                SetupWizardView {
                    startupFlow.finishWizard()
                }
                .transition(.opacity)
            case .launcher:
                launcher
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { MessageBoxOverlay() }
        .overlay { HintOverlay() }
    }

    private var launcher: some View {
        ContentView()
            .ignoresSafeArea(.all)
            .frame(minWidth: AppWindow.launcherMinSize.width, minHeight: AppWindow.launcherMinSize.height)
            .environmentObject(instanceManager)
            .environmentObject(MinecraftDownloadPageViewModel())
            .environmentObject(CardInteractionState.shared)
    }
}