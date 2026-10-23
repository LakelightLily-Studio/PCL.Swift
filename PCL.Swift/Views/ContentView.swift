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
        .background {
            ZStack {
                Color.colorBackground
                BackgroundLayer()
            }
        }
        // 主题色是计算属性，切换后需要重建视图树才能整体换色；
        // demo 分支的 ⌘R 通过 replayToken 复用同一条重建路径来重播进入动画。
        // 两个 .id() 会互相覆盖（后者胜出），所以合并成一个标识。
        .id("\(themeManager.revision)-\(demoState.replayToken)")
        // 拖自定义主题滑杆时整棵树会被 .id 重建，卡片不能再播一遍入场动画。
        .disableCardAppearAnimation(themeManager.isAdjustingCustomTheme)
        // 彩蛋效果必须"按需挂载"，不能一直挂着空值：
        // rotation3DEffect 会把整个窗口的视图树压进一个离屏合成层，
        // 即使角度是 0，那一层也照样存在——每次滚动/重绘都要重新合成整窗，
        // 表现为"所有能滑动的地方都掉帧"。contrast 同理，它是一个颜色滤镜。
        // 彩蛋触发时再挂，未触发时视图树里根本没有这两个修饰器。
        .modifier(EasterEggEffect(
            angle: easterEggManager.rotationAngle,
            axis: easterEggManager.rotationAxis,
            inverted: easterEggManager.modifyColor
        ))
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
    @ObservedObject private var dshManager: DSHLaunchManager = .shared
    
    var body: some View {
        VStack(spacing: 0) {
            ExtraButton(.iconDownloadPage, showTasksButton) {
                router.append(.tasks)
            }
            // Minecraft 与 DSH 共用这颗电源按钮，谁在跑就停谁。
            ExtraButton(.iconPower, launchManager.isRunning || dshManager.isRunning) {
                if dshManager.isRunning {
                    dshManager.stop()
                } else {
                    launchManager.stop()
                    if launchManager.isLaunching {
                        hint("已取消启动！", type: .finish)
                    } else {
                        hint("已关闭游戏！", type: .finish)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.4), value: launchManager.isRunning)
        .animation(.spring(response: 0.4), value: dshManager.isRunning)
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

/// 彩蛋的旋转与反色效果。
///
/// 只在真正生效时才挂上对应修饰器。常驻一个"角度为 0 的 rotation3DEffect"
/// 会让整棵视图树长期处在离屏合成层里，滚动时每帧都要重新合成，代价极高。
private struct EasterEggEffect: ViewModifier {
    let angle: Angle
    let axis: (CGFloat, CGFloat, CGFloat)
    let inverted: Bool

    func body(content: Content) -> some View {
        if inverted {
            content
                .rotation3DEffect(angle, axis: axis)
                .contrast(-1)
        } else if angle != .degrees(0) {
            content
                .rotation3DEffect(angle, axis: axis)
        } else {
            content
        }
    }
}
