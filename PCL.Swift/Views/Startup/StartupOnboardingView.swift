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
    /// 图标在面板坐标系里的最终位置。收尾的径向淡出要以它为中心，
    /// 而图标并不在面板正中（下方还有文案与按钮），所以不能直接写 .center。
    @State private var logoFrame: CGRect = .zero

    private var tint: Color { .color3 }
    private var tintShade: Color { .color4 }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth: CGFloat = max(1, proxy.size.width)
            let panelHeight: CGFloat = max(1, proxy.size.height)
            let compactSide: CGFloat = min(panelWidth, panelHeight)
            let logoSide: CGFloat = max(120, min(220, compactSide * 0.5))

            ZStack {
                background(logoSide: logoSide)
                foreground(logoSide: logoSide)
            }
            .frame(width: panelWidth, height: panelHeight, alignment: .center)
            .coordinateSpace(name: Self.panelSpace)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(WindowCornerRadiusReader(cornerRadius: $windowCornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: windowCornerRadius))
            .overlay(alignment: .topLeading) { closeButton }
            .onPreferenceChange(LogoFramePreferenceKey.self) { frame in
                // 只认收拢结束后的稳定值：弹簧动画过程中每帧都会上报不同的尺寸，
                // 逐帧写 @State 会让整棵视图反复重排。等宽度落到 logoSide 才记一次。
                guard properties.convertToLogo, frame.width >= logoSide - 1 else { return }
                if abs(logoFrame.midX - frame.midX) > 0.5 || abs(logoFrame.midY - frame.midY) > 0.5 {
                    logoFrame = frame
                }
            }
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

    private func background(logoSide: CGFloat) -> some View {
        GeometryReader { proxy in
            let compactSide: CGFloat = min(proxy.size.width, proxy.size.height)
            // 放射渐变的中心用单位坐标（0...1），换算自图标在面板里的落点。
            let center: UnitPoint = logoFrame == .zero
                ? .center
                : UnitPoint(
                    x: logoFrame.midX / proxy.size.width,
                    y: logoFrame.midY / proxy.size.height
                )
            // 淡出半径要够大，让线条从面板四周向图标平缓过渡，而不是围着图标一圈硬边。
            let fadeRadius: CGFloat = max(logoSide * 1.2, compactSide * 0.55)
            // 遮罩强度：收尾阶段从 0 插值到 1，线条才「逐渐」变淡而不是瞬间消失。
            let fadeIntensity: Double = properties.fadeBackgroundLines ? 1 : 0

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

                // 网格与对角线合为一层再统一加遮罩：它们共用同一个「草稿风格线条」语义，
                // 分两层各自遮罩会在视觉上出现轻微不一致的过渡边界。
                // 轨道圆环（circlesView / circleStrokeView）保持原样，收尾时仍自行收拢淡出。
                ZStack {
                    gridLines()
                    diagonalLines()
                }
                .modifier(RadialFadeOut(intensity: fadeIntensity, center: center, fadeRadius: fadeRadius))

                circlesView()
                circleStrokeView()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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
                    // 上报图标在面板里的最终落点，供背景线条做径向淡出。
                    // 必须挂在 .frame 之后：挂在 logoView 内部量到的是图片自身尺寸，
                    // 不是收拢后的画布尺寸。
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: LogoFramePreferenceKey.self,
                                value: proxy.frame(in: .named(Self.panelSpace))
                            )
                        }
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

    private static let panelSpace: String = "PCL.Swift.StartupOnboarding"

    /// 收尾时让背景线条「从四周向图标逐渐变淡、最后在图标处消失」的径向遮罩。
    ///
    /// 遮罩恒为「中心透明、外圈不透明」的径向渐变，靠 `intensity` 在 0…1 之间插值：
    /// 0 时整层完全可见（线条照常铺满），1 时图标一圈彻底让空。
    /// 之所以用 `mask` 而不是直接调各线条的 `opacity`：网格、对角线、圆环是三层独立视图，
    /// 分别淡出会出现深浅不一与接缝；遮罩对整层一次性生效，过渡必然一致。
    /// 之所以不写 `if active { ... } else { Color.black }`：那样是瞬切，没有渐变过程。
    private struct RadialFadeOut: ViewModifier {
        /// 0 = 完全不遮（线条全显示），1 = 图标处完全让空。
        let intensity: Double
        let center: UnitPoint
        /// 渐变铺开的半径：从图标中心算起，到这个距离以外遮罩完全实心。
        let fadeRadius: CGFloat

        /// 透明区占 `fadeRadius` 的比例。其余部分是「淡」的过渡带，
        /// 让线条从四周向图标逐渐变淡，而不是一圈硬边。
        private let clearRatio: Double = 0.35

        func body(content: Content) -> some View {
            content.mask {
                RadialGradient(
                    stops: [
                        // 图标处：最终完全透明，线条在此消失。
                        .init(color: .black.opacity(1 - intensity), location: 0),
                        .init(color: .black.opacity(1 - intensity), location: clearRatio),
                        // 往外逐渐恢复，到 fadeRadius 之外完全不受影响。
                        .init(color: .black, location: 1)
                    ],
                    center: center,
                    startRadius: 0,
                    endRadius: fadeRadius
                )
                // 渐入：只在收尾阶段插值，避免动画过程中遮罩提前生效。
                .animation(.easeInOut(duration: 1.1), value: intensity)
            }
        }
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
        /// 收尾时背景线条的径向淡出强度：0 保留全部线条，1 在图标处完全让空。
        var fadeBackgroundLines: Bool = false
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
            .init(delay: 0.5, animation: .interpolatingSpring(stiffness: 170, damping: 17)) { $0.convertToLogo = true },
            // 10) 线条不再是整层消失，而是从面板四周向图标逐渐变淡、最后在图标处让空。
            //     缓入缓出、持续 1.1s，和上一步的收拢弹簧错开，视觉上先收拢再淡出。
            .init(delay: 0.45, animation: .easeInOut(duration: 1.1)) { $0.fadeBackgroundLines = true }
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

/// 上报图标在面板坐标系里的位置，供背景的径向淡出确定中心。
private struct LogoFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next: CGRect = nextValue()
        if next != .zero { value = next }
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