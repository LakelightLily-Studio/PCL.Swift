//
//  MyNavigationList.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/5.
//

import SwiftUI

struct MyNavigationList: View {
    @ObservedObject private var router: AppRouter = .shared
    /// 整个列表共享一条入场时间线：所有行在同一帧开始，靠各自的 delay 错峰。
    @State private var appeared: Bool = false
    @Environment(\.disableCardAppearAnimation) private var disableEntrance
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
                RouteView(route: route, refresh: performRefresh, entranceIndex: index, appeared: appeared)
                    .onTapGesture {
                        if router.last != route.route {
                            router.removeLast()
                            router.append(route.route)
                        }
                    }
            }
        }
        .onAppear {
            guard !disableEntrance else {
                appeared = true
                return
            }
            // 下一帧再翻：同一帧里 false → true 不会产生动画。
            DispatchQueue.main.async { appeared = true }
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
    @State private var hovered: Bool = false
    @State private var selected: Bool
    @State private var lastRefresh: Date = .distantPast
    private let route: AppRoute
    private let image: ImageResource?
    private let label: String
    private let refresh: ((AppRoute) -> Void)?
    /// 在列表里的位置，用于入场错峰。
    private let entranceIndex: Int
    /// 列表级的入场开关，由 MyNavigationList 统一切换。
    private let appeared: Bool

    init(route: MyNavigationList.Route, refresh: ((AppRoute) -> Void)?, entranceIndex: Int, appeared: Bool) {
        self.route = route.route
        self.image = route.image
        self.label = route.text
        self.refresh = refresh
        self.entranceIndex = entranceIndex
        self.appeared = appeared
        self._selected = State(initialValue: AppRouter.shared.last == route.route)
    }
    
    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(selected ? Color.color3 : .clear)
                .frame(width: 4, height: selected ? 24 : 10)
            if let image {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
            Text(label)
                .font(.custom("PCLEnglish", size: 14))
            if selected, hovered, let refresh {
                Spacer(minLength: 0)
                Image(.iconRefresh)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13)
                    .contentShape(.rect)
                    .onTapGesture {
                        if Date.now.timeIntervalSince(lastRefresh) > 0.5 {
                            lastRefresh = Date.now
                            refresh(route)
                        }
                    }
                    .padding(.trailing, 6)
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovered ? Color.color2.opacity(0.1) : .clear)
        .foregroundStyle(selected ? Color.color3 : .color1)
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard hovered != isHovered else { return }
            hovered = isHovered
        }
        // 对齐 PCL2 的 MyListItem：悬停进入 120ms、离开 180ms。
        .animation(hovered ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18), value: hovered)
        .animation(.spring(response: 0.2), value: selected)
        // 逐条目入场：整列表共用一条时间线，靠 delay 错峰。
        // 只在侧边栏被重建时播一次，切子页面不会重播。
        .modifier(SidebarEntranceShape(progress: appeared ? 1 : 0))
        .animation(
            .linear(duration: SidebarEntrance.duration).delay(SidebarEntrance.delay(for: entranceIndex)),
            value: appeared
        )
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
