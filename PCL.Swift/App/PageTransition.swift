//
//  PageTransition.swift
//  PCL.Swift
//
//  页面切换的"先退场、再换页"调度。
//
//  为什么需要这一层：SwiftUI 里视图被移出视图树是瞬时的，没有"退场动画"这回事。
//  PCL2 的做法是（FormMain.PageChangeAnim）先让旧页面播退场动画，110ms 后才把
//  容器里的子控件换成新页面。要还原同样的观感，路由就不能直接驱动页面内容：
//  必须有一个中间状态——"路由已经变了，但窗口上挂的还是旧页面"。
//
//  于是这里多一层 Presentation：页面与侧边栏都只认 presentation.route，
//  AppRouter 的 path 变化只触发 request()，等退场跑完再一次性换页面。
//
//  几条约定：
//  - presentation 是一次性提交的结构体：换页面与"退场结束"必须同一帧生效。
//    分成两个 @Published 会让新页面先带着 isExiting = true 挂上去、闪一帧再回来。
//  - 退场途中又切页面：沿用同一条退场（旧页面早就淡完了），只把目标换成最新路由。
//  - 退场途中切回原页面：撤销退场，控件按原路淡回来。
//  - 侧边栏的逐条目入场只在侧边栏被重建（换页面族）时播一次；点侧边栏条目
//    切同一套侧边栏里的子页面**不重播**，所以这里不再对外提供"切页次数"。
//

import SwiftUI
import Core

@MainActor
final class PageTransition: ObservableObject {
    static let shared: PageTransition = .init()

    /// 当前真正挂在窗口上的东西。
    struct Presentation: Equatable {
        /// 正在显示的页面。退场期间仍是旧页面。
        var route: AppRoute
        /// 旧页面是否正在退场。
        var isExiting: Bool
    }

    @Published private(set) var presentation: Presentation

    /// 这次切换是否由侧边栏条目发起。
    ///
    /// 侧边栏发起时**不播侧边栏自己的退场**：点条目只是换个选中态，
    /// 整列淡出再淡回来既多余，又会在换页那一刻被截断（退场比换页窗口长），
    /// 看起来就是"动画播到一半突然复原"。
    @Published private(set) var isSidebarNavigation: Bool = false
    /// 侧边栏点击期间置位，由下一次 request 读取。
    private var sidebarNavigationPending: Bool = false

    private var swapWorkItem: DispatchWorkItem?
    private var pendingRoute: AppRoute?

    private init() {
        presentation = .init(route: AppRouter.shared.last, isExiting: false)
    }

    /// 侧边栏条目即将切换页面：标记这次切换的来源。
    ///
    /// 必须在改 `AppRouter.path` **之前**调用，`request` 才读得到。
    func noteSidebarNavigation() {
        sidebarNavigationPending = true
    }

    /// 路由变了：先播退场，退场结束再换页面。
    func request(_ route: AppRoute) {
        isSidebarNavigation = sidebarNavigationPending
        guard route != presentation.route else {
            // 又切回来了：撤销退场，控件按原路淡回来。
            cancelSwap()
            pendingRoute = nil
            sidebarNavigationPending = false
            if presentation.isExiting {
                presentation.isExiting = false
            }
            return
        }

        pendingRoute = route
        if !presentation.isExiting {
            presentation.isExiting = true
        }
        scheduleSwap()
    }

    /// 页面还没挂上时的对齐（例如进入启动器之前路由已经改过）。
    func sync() {
        guard !presentation.isExiting, pendingRoute == nil else { return }
        let route: AppRoute = AppRouter.shared.last
        guard route != presentation.route else { return }
        presentation = .init(route: route, isExiting: false)
        isSidebarNavigation = false
        sidebarNavigationPending = false
    }

    private func scheduleSwap() {
        cancelSwap()
        let workItem: DispatchWorkItem = .init { [weak self] in
            guard let self, let route = self.pendingRoute else { return }
            self.pendingRoute = nil
            self.swapWorkItem = nil
            self.presentation = .init(route: route, isExiting: false)
            self.sidebarNavigationPending = false
        }
        swapWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + PageExit.window, execute: workItem)
    }

    private func cancelSwap() {
        swapWorkItem?.cancel()
        swapWorkItem = nil
    }
}
