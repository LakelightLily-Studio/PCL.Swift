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
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    
    @EnvironmentObject private var instanceManager: InstanceManager
    
    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
                .zIndex(10)
            HStack(spacing: 0) {
                // 放在页面之上：底板做宽度动画时会短暂伸到页面区域，
                // 画在页面上方才像"侧边栏滑过去"，而不是露出一条缝。
                AppSidebarView()
                    .zIndex(1)
                AppRouterView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // 背景图片铺在内容区最底层（标题栏以下），与 PCL2 的 ImgBack 位置一致。
            .background { BackgroundImageView() }
            // 页面底色：默认是主题色的浅色，「叠加彩色背景」关掉时退回中性灰（PCL2 的 #f5f5f5）。
            //
            // **只铺内容区，不铺标题栏**：标题栏选「液态玻璃」时，玻璃采样的是它背后那层内容，
            // 底色一旦铺到标题栏下面，玻璃就永远是一块主题色板（看起来"还有原主题色"）。
            // 纯色 / 线格两档的标题栏自己画底色（NavigationBarBackgroundView），不受影响。
            .background(LauncherConfig.shared.backgroundColorful ? Color.colorBackground : Color.colorGray8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 消息框与提示条已上移到 RootView（向导阶段也要能弹），这里只留页面内的浮层。
        .overlay { ExtraButtonsOverlay() }
        // 主题色是计算属性，切换后需要重建视图树才能整体换色。
        // 用 revision 而不是主题名：自定义主题拖滑杆时只有 revision 会变。
        .id(themeManager.revision)
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
    
    var body: some View {
        VStack(spacing: 0) {
            // 新增任务时右下角的任务按钮荡开一圈水波（原版 MyExtraButton.Ribble）。
            ZStack {
                TaskAddedRipple(trigger: taskManager.tasks.count)
                ExtraButton(.iconDownloadPage, showTasksButton) {
                    router.append(.tasks)
                }
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
    
    /// 新增任务时从任务按钮荡开的水波。
    ///
    /// 对齐 PCL2 的 `MyExtraButton.Ribble()`：插入一个半透明的圆，1000ms 内放大到 13 倍
    /// 并淡到 0（AniEaseInoutFluent(Strong)），**不裁剪**——原版就是让它铺到窗口上去。
    private struct TaskAddedRipple: View {
        let trigger: Int
        @State private var progress: Double = 0
        @State private var lastTrigger: Int = 0

        var body: some View {
            Circle()
                .fill(Color.color5)
                .opacity(progress > 0 ? 0.5 * (1 - progress) : 0)
                .frame(width: 40, height: 40)
                .scaleEffect(1 + 12 * progress, anchor: .center)
                .allowsHitTesting(false)
                .onAppear { lastTrigger = trigger }
                .onChange(of: trigger) { newValue in
                    // 只有「多了一个任务」才荡一下：任务完成被移除时不该有反馈。
                    defer { lastTrigger = newValue }
                    guard newValue > lastTrigger else { return }
                    play()
                }
        }

        private func play() {
            progress = 0
            withAnimation(.timingCurve(0.7, 0, 0.3, 1, duration: 1)) {
                progress = 1
            }
            // 动画跑完后归零（此时不透明度已经是 0，看不到跳变）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                progress = 0
            }
        }
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
                // 出现 / 消失对齐 PCL2 的 MyExtraButton.Show：
                // 出现是 500ms 的 AniEaseOutBack(Weak)（延迟 60ms），消失是 100ms 的 AniEaseInFluent(Weak)。
                .animation(
                    show
                        ? .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.5).delay(0.06)
                        : .timingCurve(0.55, 0.06, 0.68, 0.19, duration: 0.1),
                    value: show
                )
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
