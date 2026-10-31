//
//  TitleBarView.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/10.
//

import SwiftUI
import Core

struct TitleBarView: View {
    /// 三色按钮占用的宽度：窗口左侧 20pt 起始 + 两个 14pt 按钮 + 间距 + 尾部留白。
    ///
    /// 缩放按钮是恒隐藏的（见 `AppWindow`），所以这里只给两个按钮留位。
    static let trafficLightReservedWidth: CGFloat = 62

    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var flagsManager: FlagsManager = .shared
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    /// 直接观察 ThemeManager：拖自定义滑杆时视图树不重建（revision 不动），
    /// 只有观察 palette 的视图才会实时换色。标题栏是用户最先看的地方，必须跟着变。
    @ObservedObject private var themeManager: ThemeManager = .shared

    // MARK: - 主 / 子标题栏的切换状态
    //
    // PCL2 的 PanTitleMain 与 PanTitleInner 是两个叠在一起、各自做动画的 Grid：
    // 旧的那一套先退场并折叠，新的延迟 200ms 再进场。这里用同一套状态机。
    @State private var mainMounted: Bool = true
    @State private var subMounted: Bool = false
    @State private var mainOpacity: Double = 1
    @State private var mainOffset: CGFloat = 0
    @State private var subOpacity: Double = 0
    @State private var subOffset: CGFloat = 0
    /// 当前已经切到哪一套（用来忽略重复的 onChange）。
    @State private var settledIsSub: Bool = false
    /// 子栏正在显示的标题。
    ///
    /// 不能直接读 router.title：返回上级页面时路由先变，子栏还要再挂 150ms 播退场，
    /// 那段时间里 router.title 已经是上级页面的——根页面本来就没有标题，
    /// 取到的会是「错误：当前页面（launch）没有标题」。表现出来就是点返回后
    /// 标题栏闪一下错误文案，等回到上级页面才消失。
    /// 所以只在**仍处于子页面**时更新它，退场期间保持旧标题。
    @State private var displayedTitle: String = AppRouter.shared.title
    /// 快速来回切页时丢弃过期的延迟任务。
    @State private var transitionToken: Int = 0

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationBarBackgroundView()
            // 主栏与子栏是两层叠在一起的视图，切页时旧的一套先退场、新的延迟 200ms 再进场
            // （PCL2 的 FormMain.PanTitleMain / PanTitleInner，见 TitleBarTransition）。
            if mainMounted {
                mainBar
                    .opacity(mainOpacity)
                    .offset(x: mainOffset)
                    .allowsHitTesting(mainOpacity > 0.5)
                    // 三色按钮由系统画在透明标题栏里（关闭 + 最小化，缩放按钮恒隐藏），
                    // 内容从这里起排，留出按钮组占用的宽度，避免标题 Logo 压到按钮上。
                    .padding(.leading, Self.trafficLightReservedWidth)
            }
            if subMounted {
                subBar
                    .opacity(subOpacity)
                    .offset(x: subOffset)
                    .allowsHitTesting(subOpacity > 0.5)
                    .padding(.leading, Self.trafficLightReservedWidth)
            }
        }
        .frame(height: AppWindow.titleBarHeight)
        .onAppear {
            displayedTitle = router.title
            // 初次挂载时直接对齐，不播动画（正常是从启动页进来，两栏本来就是默认状态）。
            let isSub: Bool = router.isSubPage
            guard settledIsSub != isSub else { return }
            settledIsSub = isSub
            mainMounted = !isSub
            subMounted = isSub
            mainOpacity = isSub ? 0 : 1
            mainOffset = 0
            subOpacity = isSub ? 1 : 0
            subOffset = 0
        }
        .onChange(of: router.isSubPage) { newValue in
            playTransition(toSub: newValue)
        }
        .onChange(of: router.last) { _ in
            // 只在还停在子页面时换标题：返回根页面时保持旧标题，让子栏带着它退场。
            guard router.isSubPage else { return }
            displayedTitle = router.title
        }
    }

    /// 标题栏前景色。
    ///
    /// 「液态玻璃」是一块浅色玻璃（不掺主题色），白字会糊在背景里，所以那一档换成深色；
    /// 「纯色 / 线格」两档都是主题色底，仍然用白字。
    private var barForeground: Color {
        LauncherConfig.shared.navigationBarBackground == .liquidGlass ? .color1 : .white
    }

    /// 主页面标题栏：居中的页签按钮组 + 靠左的标识。
    private var mainBar: some View {
        ZStack(alignment: .leading) {
            // 主页按钮组始终居中；Logo 的位置由设置决定（默认居左，
            // 与 PCL 原版一致；选择居中时按钮组仍在原位，两者不重叠）。
            HStack {
                Spacer()
                PageButton("启动", .iconLaunchPage, .launch)
                PageButton("下载", .iconDownloadPage, .download)
                if flagsManager.isEnabled(.multiplayer) {
                    PageButton("联机", .iconMultiplayerPage, .multiplayer)
                }
                PageButton("设置", .iconSettingsPage, .settings)
                PageButton("更多", .iconMorePage, .more)
                Spacer()
            }

            // 标识固定靠左：位置选项已移除，避免和居中的按钮组抢位置。
            HStack {
                logoView
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 子页面标题栏：返回按钮 + 页面标题。
    private var subBar: some View {
        HStack {
            WindowButton(.btnBack) {
                router.removeLast()
            }
            MyText(displayedTitle, size: 16, color: barForeground)
        }
    }

    // MARK: - 主 / 子标题栏切换

    /// 主页面 → 子页面：主栏 150ms 淡出并右移 12pt，子栏延迟 200ms 进场
    /// （150ms 淡入 + 350ms 从 -16 滑到 0）。
    /// 子页面 → 主页面：子栏 150ms 淡出并左移 18pt，主栏延迟 200ms 回来。
    /// 数值全部取自 PCL2 的 FormMain.PageChangeActual / PageChangeExit。
    private func playTransition(toSub isSub: Bool) {
        guard settledIsSub != isSub else { return }
        settledIsSub = isSub
        transitionToken += 1
        let token: Int = transitionToken

        if isSub {
            withAnimation(.linear(duration: TitleBarTransition.leaveDuration)) {
                mainOpacity = 0
            }
            withAnimation(TitleBarTransition.leave) {
                mainOffset = TitleBarTransition.mainLeaveOffset
            }
            subMounted = true
            subOpacity = 0
            subOffset = TitleBarTransition.subStartOffset
            run(after: TitleBarTransition.leaveDuration, token: token) {
                mainMounted = false
            }
            run(after: TitleBarTransition.enterDelay, token: token) {
                withAnimation(TitleBarTransition.fadeIn) { subOpacity = 1 }
                withAnimation(TitleBarTransition.slideIn) { subOffset = 0 }
            }
        } else {
            withAnimation(.linear(duration: TitleBarTransition.leaveDuration)) {
                subOpacity = 0
            }
            withAnimation(TitleBarTransition.leave) {
                subOffset = TitleBarTransition.subLeaveOffset
            }
            mainMounted = true
            mainOpacity = 0
            mainOffset = TitleBarTransition.mainLeaveOffset
            run(after: TitleBarTransition.leaveDuration, token: token) {
                subMounted = false
            }
            run(after: TitleBarTransition.enterDelay, token: token) {
                withAnimation(TitleBarTransition.fadeIn) { mainOpacity = 1 }
                withAnimation(TitleBarTransition.slideIn) { mainOffset = 0 }
            }
        }
    }

    /// 延迟执行，并用 token 丢弃过期的那一批（快速来回切页时）。
    private func run(after delay: Double, token: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard token == transitionToken else { return }
            action()
        }
    }

    /// 标题栏左侧的标识：默认 Logo、自定义文本或自定义图片。
    ///
    /// 三种形态共用同一块布局位置，切换时不会让右侧按钮组跳动。
    @ViewBuilder
    private var logoView: some View {
        switch LauncherConfig.shared.titleBarLogoType {
        case .none:
            EmptyView()
        case .logo:
            HStack(spacing: 4) {
                // 标题栏沿用 PCL 的白色线条字标（配合右侧的 "Swift" 标签读作 PCL.Swift）；
                // App 图标只用在开场动画里，不要挪到这里。
                Image(.iconTitleLogo)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(barForeground)
                    .frame(height: 19)
                MyTag("Swift", labelColor: .color2)

                if Metadata.debugMode {
                    MyTag("Debug", backgroundColor: Color(0x9BF00B))
                }
            }
        case .text:
            MyText(
                LauncherConfig.shared.titleBarText.isEmpty ? "PCL.Swift" : LauncherConfig.shared.titleBarText,
                size: 16,
                color: barForeground
            )
            .lineLimit(1)
        case .image:
            if let url = LauncherConfig.shared.titleBarImageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
            } else {
                Image(.iconTitleLogo)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(barForeground)
                    .frame(height: 19)
            }
        }
    }
}

/// 主 / 子标题栏切换的时序，全部取自 PCL2 的 FormMain：
///
/// - 主栏退场：150ms 淡出（线性）+ 150ms 右移 12pt（AniEaseInFluent(Weak) = t²）
/// - 子栏进场：延迟 200ms，150ms 淡入（AniEaseOutFluent）+ 350ms 从 -16 滑到 0（AniEaseOutBack(Weak)）
/// - 子栏退场：150ms 淡出 + 150ms 左移 18pt
/// - 主栏回来：延迟 200ms，150ms 淡入 + 350ms 从 +12 滑回 0
private enum TitleBarTransition {
    /// 退场时长（淡出与位移都是 150ms）。
    static let leaveDuration: Double = 0.15
    /// 进场延迟（PCL2 的 AaX(..., 350, 200) 里的 200）。
    static let enterDelay: Double = 0.2
    /// 主栏退场时右移的距离。
    static let mainLeaveOffset: CGFloat = 12
    /// 子栏退场时左移的距离。
    static let subLeaveOffset: CGFloat = -18
    /// 子栏进场时的起点（PanTitleInner 的 Margin="-16,0,0,0"）。
    static let subStartOffset: CGFloat = -16

    /// AniEaseInFluent(Weak) = t²。
    static let leave: Animation = .timingCurve(0.55, 0.06, 0.68, 0.19, duration: 0.15)
    /// AniEaseOutFluent(Middle) = 1-(1-t)³。
    static let fadeIn: Animation = .timingCurve(0.33, 1, 0.68, 1, duration: 0.15)
    /// AniEaseOutBack(Weak)：末尾约 10% 过冲后落回。
    static let slideIn: Animation = .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.35)
}

private struct PageButton: View {
    @ObservedObject private var router: AppRouter = .shared
    /// 观察配置：切到「液态玻璃」时前景色要跟着从白换成深色。
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var hovered: Bool = false
    private var isRoot: Bool { router.root == route }
    /// 标题栏是不是浅色的玻璃：那一档白字看不清，得换深色。
    private var isGlassBar: Bool {
        LauncherConfig.shared.navigationBarBackground == .liquidGlass
    }
    private let label: String
    private let icon: ImageResource
    private let route: AppRoute
    
    init(_ label: String, _ icon: ImageResource, _ route: AppRoute) {
        self.label = label
        self.icon = icon
        self.route = route
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(backgroundColor)
            HStack(spacing: 7) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16)
                    .foregroundStyle(foregroundColor)
                MyText(label, color: foregroundColor)
            }
        }
        .frame(width: 78, height: 27)
        .contentShape(Rectangle())
        .onHover { hovered in
            self.hovered = hovered
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if router.root != route {
                        router.setRoot(route)
                    }
                }
        )
        // 顶栏页签对齐 PCL2 的 MyRadioButton（MyRadioBox 的常量）：
        // 鼠标进入 100ms、离开 200ms；选中态切换同样 100ms。
        .animation(hovered ? .easeOut(duration: 0.1) : .easeOut(duration: 0.2), value: hovered)
        .animation(.easeOut(duration: 0.1), value: isRoot)
    }
    
    private var foregroundColor: Color {
        if isRoot {
            // 深色外观下与左侧边栏的选中项统一：那边选中用的就是 color3（主题色）。
            // 浅色仍用更深的 color2——白底药丸上 color3 偏浅，压不住。
            return Color.isDark ? .color3 : .color2
        }
        return isGlassBar ? .color1 : .white
    }
    
    private var backgroundColor: Color {
        if isRoot { return .white }
        guard hovered else { return .clear }
        // 悬停底色跟着前景色走：白字配半透明白，深色字配一点黑，两种底上都看得见。
        return isGlassBar ? Color.color1.opacity(0.08) : .white.opacity(0.25)
    }
}
