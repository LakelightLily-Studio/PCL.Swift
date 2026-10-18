//
//  StartupOnboardingView.swift
//  PCL.Swift
//
//  首次启动的开场动画：主题橙铺底 → 轨道节点 → 网格与对角线 → 收拢为 Logo
//  → 文案与「继续」按钮自下滑入。
//
//  移植自 XcodeNewBegining 的 XcodeOnBoardingView，做了三处改动：
//  1. 主色改为主题色（默认主题橙），而不是系统强调色；
//  2. 收尾展示的图标换成启动器标题 Logo，文案换成 PCL.Swift 的欢迎语；
//  3. 时间线改成 macOS 12 可用的写法（App 的最低部署目标是 12.0，
//     原实现用了 AnyLayout / .bouncy / .rect 等 13+ API）。
//

import SwiftUI
import Core

struct StartupOnboardingView: View {
    /// 点击「继续」后要执行的动作，由 RootView 接到 StartupFlow 上。
    let onContinue: () -> Void

    /// 动画状态机：每个标记/数值对应一个视觉阶段。
    @State private var properties: Properties = .init()
    @State private var windowCornerRadius: CGFloat = 12

    private var tint: Color { .color3 }
    private var tintShade: Color { .color4 }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth: CGFloat = max(1, proxy.size.width)
            let panelHeight: CGFloat = max(1, proxy.size.height)
            let compactSide: CGFloat = min(panelWidth, panelHeight)
            let logoSide: CGFloat = max(120, min(220, compactSide * 0.5))

            ZStack {
                background
                foreground(logoSide: logoSide)
            }
            .frame(width: panelWidth, height: panelHeight, alignment: .center)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(WindowCornerRadiusReader(cornerRadius: $windowCornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: windowCornerRadius))
            .overlay(alignment: .topLeading) { closeButton }
        }
        // 开场动画要铺满整扇窗口：标题栏透明且内容延伸到标题栏下方，
        // 否则顶部会留一条 28pt 的系统底色，与主题色断层。
        .ignoresSafeArea()
        .onAppear {
            // 视图重复出现时不重复播放整段动画。
            guard !properties.animateMainCircle else { return }
            Task { await startAnimationSequence() }
        }
    }

    // MARK: - 背景层

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                // 第 1 阶段主色铺底：主圆扩散，建立整体主题色氛围。
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint, tintShade],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(properties.animateMainCircle ? 2 : 0)

                gridLines()
                circlesView()
                circleStrokeView()
                diagonalLines()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(properties.convertToLogo ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.5), value: properties.convertToLogo)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - 前景层

    @ViewBuilder
    private func foreground(logoSide: CGFloat) -> some View {
        GeometryReader { proxy in
            let panelWidth: CGFloat = max(1, proxy.size.width)
            let panelHeight: CGFloat = max(1, proxy.size.height)

            VStack(spacing: 0) {
                logoView
                    // 末段把整块画布收拢为 Logo 尺寸；其余阶段保持铺满面板。
                    .frame(
                        width: properties.convertToLogo ? logoSide : panelWidth,
                        height: properties.convertToLogo ? logoSide : panelHeight
                    )

                contentView
                    .opacity(properties.convertToLogo ? 1 : 0)
                    .offset(y: properties.convertToLogo ? 0 : 60)
            }
            .frame(width: panelWidth, height: panelHeight, alignment: .center)
        }
    }

    /// 收尾展示的标识：直接用 App 图标本体，而不是「PCL」字标。
    private var logoView: some View {
        Image(.iconAppIcon)
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 28)
            .compositingGroup()
            .blur(radius: properties.convertToLogo ? 0 : 24)
            .opacity(properties.convertToLogo ? 1 : 0)
            .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    private var contentView: some View {
        VStack(spacing: 15) {
            Text("欢迎使用 PCL.Swift")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)

            Text("基于 SwiftUI 重构的 Plain Craft Launcher")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))

            Button(action: onContinue) {
                Text("继续")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(maxWidth: 230)
                    .padding(.vertical, 11)
                    .background(
                        Capsule().fill(Color.white)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.top, 22)
    }

    private var closeButton: some View {
        Button(action: handleClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                // 图标固定白色，确保在主题色上都有稳定对比度。
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 16, height: 16)
                .background(Color.white.opacity(0.24), in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(.leading, 16)
        .padding(.top, 16)
    }

    // MARK: - 动画元素

    @ViewBuilder
    private func circlesView() -> some View {
        ZStack {
            ForEach(1...4, id: \.self) { index in
                let rotation: CGFloat = (CGFloat(index) / 4.0) * 360
                let extraRotation: CGFloat = properties.positionCircles ? 20 : 0
                let extraOffset: CGFloat = index % 2 != 0 ? 40 : -20

                Circle()
                    .fill(Color.white)
                    .frame(width: properties.circleSize, height: properties.circleSize)
                    .animation(.easeInOut(duration: 0.05).delay(0.35), value: properties.positionCircles)
                    .scaleEffect(properties.positionCircles ? 0 : 1)
                    .offset(x: properties.positionCircles ? (120 + extraOffset) : properties.circleOffset)
                    .rotationEffect(.degrees(rotation + extraRotation))
                    .animation(.easeInOut(duration: 0.2).delay(0.2), value: properties.positionCircles)
            }
        }
        .compositingGroup()
        .scaleEffect(properties.circleScale)
    }

    @ViewBuilder
    private func circleStrokeView() -> some View {
        ZStack {
            // 中心圆环先展开再淡出，为最终 Logo 收拢让位。
            Circle()
                .trim(from: 0, to: properties.animateStrokes ? 1 : 0)
                .stroke(Color.white, lineWidth: 1)
                .frame(width: 70, height: 70)
                .scaleEffect(properties.convertToLogo ? 2 : 1)

            ForEach(1...4, id: \.self) { index in
                let rotation: CGFloat = (CGFloat(index) / 4.0) * 360
                // +12 用于对齐 circlesView 的轨道几何起点。
                let extraRotation: CGFloat = 20 + 12
                let extraOffset: CGFloat = index % 2 != 0 ? 120 : 0
                // 外层两圈刻意降低透明度，用于保留层次深度。
                let isFaded: Bool = index == 3 || index == 4

                Circle()
                    .trim(from: 0, to: properties.animateStrokes ? 1 : 0)
                    .stroke(Color.white.opacity(isFaded ? 0.3 : 1), lineWidth: 1)
                    .frame(width: 200 + extraOffset, height: 200 + extraOffset)
                    .rotationEffect(.degrees(rotation + extraRotation))
            }
        }
        .compositingGroup()
        .scaleEffect(properties.convertToLogo ? 1.5 : 1)
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    @ViewBuilder
    private func gridLines() -> some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        // 使用 tertiary 透明度，让网格保持「弱背景结构」角色。
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 1, height: properties.animateGridLines ? nil : 0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .scaleEffect(y: index == 1 || index == 3 ? -1 : 1)
                }
            }

            VStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: properties.animateGridLines ? nil : 0, height: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .scaleEffect(x: index == 1 || index == 3 ? -1 : 1)
                }
            }
        }
        .compositingGroup()
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    @ViewBuilder
    private func diagonalLines() -> some View {
        ZStack {
            Rectangle()
                // 对角辅助线之一，与网格共用弱化颜色。
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: properties.animateDiagonalLines ? nil : 0)
                .padding(.vertical, -100)
                .frame(maxWidth: .infinity, alignment: .top)
                .rotationEffect(.degrees(-39))

            Rectangle()
                // 镜像方向的对角辅助线。
                .fill(Color.white.opacity(0.14))
                .frame(width: 1, height: properties.animateDiagonalLines ? nil : 0)
                .padding(.vertical, -100)
                .frame(maxWidth: .infinity, alignment: .top)
                .rotationEffect(.degrees(39))
        }
        .compositingGroup()
        .opacity(properties.convertToLogo ? 0 : 1)
    }

    // MARK: - 时间线

    /// 定义所有动画阶段的可变状态。
    struct Properties {
        var animateMainCircle: Bool = false
        var circleSize: CGFloat = 50
        var circleOffset: CGFloat = 0
        var circleScale: CGFloat = 0
        var positionCircles: Bool = false
        var animateStrokes: Bool = false
        var animateGridLines: Bool = false
        var animateDiagonalLines: Bool = false
        var convertToLogo: Bool = false
    }

    private struct AnimationStep {
        let delay: Double
        let animation: Animation
        let update: (inout Properties) -> Void
    }

    @MainActor
    private func startAnimationSequence() async {
        let steps: [AnimationStep] = [
            // 1) 扩散主题背景主圆。
            .init(delay: 0.1, animation: .easeInOut(duration: 0.5)) { $0.animateMainCircle = true },
            // 2) 轨道系统从 0 缩放弹出。
            .init(delay: 0.15, animation: .interpolatingSpring(stiffness: 260, damping: 14)) { $0.circleScale = 1 },
            // 3) 轨道节点向外推开。
            .init(delay: 0.3, animation: .interpolatingSpring(stiffness: 200, damping: 15)) { $0.circleOffset = 50 },
            // 4) 轨道节点收缩为小标记点。
            .init(delay: 0.1, animation: .interpolatingSpring(stiffness: 240, damping: 15)) { $0.circleSize = 5 },
            // 5) 旋转并定位轨道节点到最终位置。
            .init(delay: 0.25, animation: .linear(duration: 0.4)) { $0.positionCircles = true },
            // 6) 绘制圆形描边网络。
            .init(delay: 0.35, animation: .linear(duration: 1)) { $0.animateStrokes = true },
            // 7) 显示背景网格线。
            .init(delay: 0.3, animation: .linear(duration: 0.6)) { $0.animateGridLines = true },
            // 8) 显示对角引导线。
            .init(delay: 0.15, animation: .linear(duration: 0.5)) { $0.animateDiagonalLines = true },
            // 9) 场景收拢为 Logo，并显示内容区域。
            .init(delay: 0.5, animation: .interpolatingSpring(stiffness: 170, damping: 17)) { $0.convertToLogo = true }
        ]

        for step in steps {
            try? await Task.sleep(seconds: step.delay)
            withAnimation(step.animation) {
                step.update(&properties)
            }
        }
    }

    private func handleClose() {
        NSApplication.shared.terminate(nil)
    }
}

/// 读取系统窗口圆角，让画布裁切与窗口外壳一致。
private struct WindowCornerRadiusReader: NSViewRepresentable {
    @Binding var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            updateCornerRadius(from: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            updateCornerRadius(from: window)
        }
    }

    private func updateCornerRadius(from window: NSWindow) {
        let frameRadius: CGFloat = window.contentView?.superview?.layer?.cornerRadius ?? 0
        let contentRadius: CGFloat = window.contentView?.layer?.cornerRadius ?? 0
        let radiusFromWindow: CGFloat = max(frameRadius, contentRadius)
        let resolvedRadius: CGFloat = radiusFromWindow > 0 ? radiusFromWindow : defaultCornerRadiusForCurrentSystem()

        if abs(cornerRadius - resolvedRadius) > 0.1 {
            cornerRadius = resolvedRadius
        }
    }

    private func defaultCornerRadiusForCurrentSystem() -> CGFloat {
        let majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion >= 26 { return 16 }
        if majorVersion >= 15 { return 12 }
        return 10
    }
}