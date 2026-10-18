//
//  ContentView.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/8.
//

import SwiftUI
import UniformTypeIdentifiers
import Core

struct ContentView: View {
    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var easterEggManager: EasterEggManager = .shared
    @ObservedObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var demoState: DemoState = .shared
    
    @EnvironmentObject private var instanceManager: InstanceManager
    
    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
                .zIndex(10)
            HStack(spacing: 0) {
                AppSidebarView()
                AppRouterView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 消息框与提示条已上移到 RootView（向导阶段也要能弹），这里只留页面内的浮层。
        .overlay { ExtraButtonsOverlay() }
        .background(Color.colorBackground)
        // 主题色是计算属性，切换后需要重建视图树才能整体换色；
        // demo 分支的 ⌘R 通过 replayToken 复用同一条重建路径来重播进入动画。
        // 两个 .id() 会互相覆盖（后者胜出），所以合并成一个标识。
        .id("\(themeManager.current.rawValue)-\(demoState.replayToken)")
        .rotation3DEffect(easterEggManager.rotationAngle, axis: easterEggManager.rotationAxis)
        .contrast(easterEggManager.modifyColor ? -1 : 1)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { item, error in
                if let error {
                    err("处理拖拽失败：\(error.localizedDescription)")
                    hint("处理拖拽失败：\(error.localizedDescription)", type: .critical)
                    return
                }
                guard let url = item else {
                    hint("处理拖拽失败：发生未知错误。", type: .critical)
                    return
                }
                Task {
                    await FileDropHandler.handle(url, instanceManager: instanceManager)
                }
            }
            return true
        }
    }
}


private struct ExtraButtonsOverlay: View {
    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var launchManager: MinecraftLaunchManager = .shared
    @ObservedObject private var taskManager: TaskManager = .shared
    
    var body: some View {
        VStack(spacing: 0) {
            ExtraButton(.iconDownloadPage, showTasksButton) {
                router.append(.tasks)
            }
            ExtraButton(.iconPower, launchManager.isRunning) {
                launchManager.stop()
                if launchManager.isLaunching {
                    hint("已取消启动！", type: .finish)
                } else {
                    hint("已关闭游戏！", type: .finish)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.4), value: launchManager.isRunning)
        .animation(.spring(response: 0.4), value: showTasksButton)
    }
    
    private var showTasksButton: Bool {
        !taskManager.tasks.filter(\.display).isEmpty && router.last != .tasks
    }
    
    private struct ExtraButton: View {
        @State private var hovered: Bool = false
        @State private var pressed: Bool = false
        private let icon: ImageResource
        private let show: Bool
        private let onClick: () -> Void
        
        init(_ icon: ImageResource, _ show: Bool, onClick: @escaping () -> Void) {
            self.icon = icon
            self.show = show
            self.onClick = onClick
        }
        
        var body: some View {
            Circle()
                .fill(hovered ? Color.color4 : .color3)
                .frame(width: show ? 40 : 1)
                .overlay {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .foregroundStyle(Color.color8)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in pressed = true }
                        .onEnded { _ in
                            pressed = false
                            onClick()
                        }
                )
                .onHover { hovered = $0 }
                .scaleEffect(show ? (pressed ? 0.85 : 1) : 0, anchor: .center)
                .padding(show ? 4 : 0)
                .animation(.linear(duration: 0.15), value: hovered)
                .animation(.easeOut(duration: 0.15), value: pressed)
                .animation(.spring(response: 0.4), value: show)
        }
    }
}