//
//  MyNavigationList.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/5.
//

import SwiftUI

/// 侧边栏的条目列表。
///
/// 每一条对应 PCL2 的 MyListItem（Type=RadioBox、Height=36、IsScaleAnimationEnabled=False）：
/// 左侧 6pt 的勾选条列、34pt 的图标列、4pt 的图标与文字间距，
/// 悬停底色是 ColorBrushBg1（color7 的 75%），按下时整条缩到 0.98。
struct MyNavigationList: View {
    @ObservedObject private var router: AppRouter = .shared
    private let routes: [Route]
    private let performRefresh: ((AppRoute) -> Void)?
    
    init(_ routes: Route..., performRefresh: ((AppRoute) -> Void)? = nil) {
        self.init(routeList: routes, performRefresh: performRefresh)
    }
    
    init(routeList: [Route], performRefresh: ((AppRoute) -> Void)? = nil) {
        self.routes = routeList
        self.performRefresh = performRefresh
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(routes.enumerated()), id: \.element.route) { index, route in
                RouteView(
                    route: route,
                    refresh: performRefresh,
                    entranceIndex: index,
                    exitDelay: SidebarExit.delay(for: index, count: routes.count),
                    // 点击必须由条目自己的手势处理：条目里挂了一个 minimumDistance 为 0 的
                    // DragGesture（按下缩放），它会先认领这次按压，外层 onTapGesture 就再也收不到了。
                    onSelect: {
                        guard router.last != route.route else { return }
                        // 先标记来源：侧边栏发起的切换不播侧边栏自己的退场。
                        PageTransition.shared.noteSidebarNavigation()
                        router.removeLast()
                        router.append(route.route)
                    }
                )
                // 这里**不要**再按切页次数换 .id：那会让每次点侧边栏都重播一遍
                // 逐条目入场（PCL2 的 TriggerShowAnimation 是整页重建时才播的）。
                // 侧边栏本身在换页面族时（启动 → 版本选择、下载 → 资源详情…）会整个重建，
                // 那时新实例的 appeared 从 false 开始，入场动画照常播一次。
            }
        }
    }
    
    struct Route {
        let route: AppRoute
        let image: ImageResource?
        let text: String
        
        init(_ route: AppRoute, _ image: ImageResource?, _ text: String) {
            self.route = route
            self.image = image
            self.text = text
        }
    }
}

private struct RouteView: View {
    @ObservedObject private var router: AppRouter = .shared
    @Environment(\.disableCardAppearAnimation) private var disableEntrance
    /// 页面是否正在退场（由 AppSidebarView 注入）。
    @Environment(\.pageExiting) private var pageExiting
    @State private var hovered: Bool = false
    @State private var pressed: Bool = false
    @State private var selected: Bool
    @State private var lastRefresh: Date = .distantPast
    /// 逐条目入场进度。换页时整行会换身份重建，所以它自然从 0 重新开始。
    @State private var appeared: Bool = false
    private let route: AppRoute
    private let image: ImageResource?
    private let label: String
    private let refresh: ((AppRoute) -> Void)?
    /// 在列表里的位置，用于入场错峰。
    private let entranceIndex: Int
    /// 退场延迟：PCL2 把 70ms 平摊给整列（70 / Controls.Count * Id）。
    private let exitDelay: Double
    /// 点中条目时切换页面。由手势自己调用，见 body 里的说明。
    private let onSelect: () -> Void

    init(
        route: MyNavigationList.Route,
        refresh: ((AppRoute) -> Void)?,
        entranceIndex: Int,
        exitDelay: Double,
        onSelect: @escaping () -> Void
    ) {
        self.route = route.route
        self.image = route.image
        self.label = route.text
        self.refresh = refresh
        self.entranceIndex = entranceIndex
        self.exitDelay = exitDelay
        self.onSelect = onSelect
        self._selected = State(initialValue: AppRouter.shared.last == route.route)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 勾选条：PCL2 的 RectCheck 是 5pt 宽、圆角 2、上下各留 6pt，
            // 未选中时高度收成 0，选中时 200ms + 300ms 两段长开。
            Rectangle()
                // 与悬停底色同一条规矩：未选中用同一颜色把不透明度降到 0，
                // 不要 .clear（透明黑会在收缩时先发灰）。
                .fill(Color.color3.opacity(selected ? 1 : 0))
                .frame(width: 5, height: selected ? 24 : 0)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(width: 6, alignment: .leading)

            if let image {
                // 图标列 34pt：左 6、图标 20、右 8，与 PCL2 的 ColumnLogo 与 PathLogo 边距一致。
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
            }

            Text(label)
                .font(.custom("PCLEnglish", size: 14))
                .padding(.leading, 4)

            Spacer(minLength: 0)

            if selected, hovered, let refresh {
                Image(.iconRefresh)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13)
                    .contentShape(.rect)
                    // 高优先级：条目本身有一个 minimumDistance 为 0 的拖动手势，
                    // 普通 onTapGesture 会被它抢走，刷新按钮就点不动了。
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            guard Date.now.timeIntervalSince(lastRefresh) > 0.5 else { return }
                            lastRefresh = Date.now
                            refresh(route)
                        }
                    )
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 悬停底色是 PCL2 的 ColorBrushBg1（#bee0eafd，即 color7 的 75%）。
        // 非悬停态用**同一个颜色把不透明度降到 0**，不要写 .clear：
        // Color.clear 是透明黑，淡出时 RGB 会一路往黑走，肉眼看到的就是
        // 「蓝色褪掉 → 灰一段时间 → 才变白」。
        .background(Color.color7.opacity(hovered ? 0.745 : 0))
        // 选中时用主色（Height < 40 的那一档 ColorBrush3）。
        .foregroundStyle(selected ? Color.color3 : .color1)
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard hovered != isHovered else { return }
            hovered = isHovered
        }
        // 按下时整条缩到 0.98（PCL2 的 AaScaleTransform(Me, 0.98)），松手时切换页面。
        // 两件事必须在同一个手势里做：早先是「条目内 simultaneousGesture 管缩放 +
        // 外层 onTapGesture 管切换」，结果外层点击被这个 minimumDistance 为 0 的
        // 拖动抢走，点条目完全没反应。
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                }
                .onEnded { value in
                    pressed = false
                    // 位移超过 4pt 当作拖动：按住后拖到别处松手不该切页面。
                    guard abs(value.translation.width) <= 4, abs(value.translation.height) <= 4 else { return }
                    onSelect()
                }
        )
        .scaleEffect(pressed ? 0.98 : 1, anchor: .center)
        // 对齐 PCL2 的 MyListItem：悬停进入 120ms、离开 180ms。
        .animation(hovered ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18), value: hovered)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .animation(.spring(response: 0.2), value: selected)
        // 逐条目入场：整列表共用一条时间线，靠 delay 错峰。
        // 只在侧边栏被重建时播一次——点侧边栏条目切子页面不重播。
        .modifier(SidebarEntranceShape(progress: appeared ? 1 : 0))
        .animation(
            .linear(duration: SidebarEntrance.duration).delay(SidebarEntrance.delay(for: entranceIndex)),
            value: appeared
        )
        // 逐条目退场：50ms 线性淡出 + 左移 6pt，整列共用 70ms 错峰窗口
        // （PCL2 的 MyPageLeft.TriggerHideAnimation 的 AnimatedControl 分支）。
        .modifier(ControlExitShape(
            progress: pageExiting ? 1 : 0,
            offset: CGSize(width: SidebarExit.offset, height: 0),
            enabled: !disableEntrance
        ))
        .animation(
            pageExiting && !disableEntrance
                ? .linear(duration: SidebarExit.duration).delay(exitDelay)
                : nil,
            value: pageExiting
        )
        .onAppear {
            guard !disableEntrance else {
                appeared = true
                return
            }
            // 下一帧再翻：同一帧里 false → true 不会产生动画。
            DispatchQueue.main.async { appeared = true }
        }
        .onChange(of: router.last) { newValue in
            selected = newValue == route
        }
    }
}

#Preview {
    MyNavigationList(
        .init(.launch, .iconLaunchPage, "启动")
    )
    .frame(width: 150)
    .padding()
    .background(.white)
}
