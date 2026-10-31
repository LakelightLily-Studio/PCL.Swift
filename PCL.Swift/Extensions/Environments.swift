//
//  Environments.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/13.
//

import SwiftUI

private struct CardIndexKey: EnvironmentKey {
    public static let defaultValue: Int = 0
}

private struct DisableCardAppearAnimationKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

private struct DisableHoverAnimationKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

/// 页面是否正在退场。由 AppRouterView / AppSidebarView 按 PageTransition 的状态注入，
/// 卡片与侧边栏条目据此播放退场动画（见 ControlExit.swift）。
private struct PageExitingKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

/// 当前视图是否位于卡片内容里。
///
/// PCL2 的 GetAllAnimControls 遇到 MyCard 就不再往里遍历：卡片是页面级控件，
/// 卡片**内部**的提示条（MyHint / 这里的 MyTip）不单独播入场 / 退场，
/// 跟着卡片一起动即可。MyCard / StaticCard 会给自己的内容注入 true。
private struct InsideCardKey: EnvironmentKey {
    public static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var cardIndex: Int {
        get { self[CardIndexKey.self] }
        set { self[CardIndexKey.self] = newValue }
    }
    
    var disableCardAppearAnimation: Bool {
        get { self[DisableCardAppearAnimationKey.self] }
        set { self[DisableCardAppearAnimationKey.self] = newValue }
    }
    
    var disableHoverAnimation: Bool {
        get { self[DisableHoverAnimationKey.self] }
        set { self[DisableHoverAnimationKey.self] = newValue }
    }
    
    var pageExiting: Bool {
        get { self[PageExitingKey.self] }
        set { self[PageExitingKey.self] = newValue }
    }

    var isInsideCard: Bool {
        get { self[InsideCardKey.self] }
        set { self[InsideCardKey.self] = newValue }
    }
}

extension View {
    /// 强制显示滚动条。
    ///
    /// macOS 默认是"滚动时才显示"，用户看到一屏内容时根本不知道右边还有东西。
    /// scrollIndicators(.visible) 是 macOS 13 才有的 API，12.0 上退回原样
    /// （那时只能靠系统设置里的「始终显示滚动条」）。
    @ViewBuilder
    func alwaysShowScrollIndicators() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.visible)
        } else {
            self
        }
    }

    func cardIndex(_ index: Int) -> some View {
        environment(\.cardIndex, index)
    }
    
    func disableCardAppearAnimation(_ disabled: Bool = true) -> some View {
        environment(\.disableCardAppearAnimation, disabled)
    }
    
    func disableHoverAnimation(_ disabled: Bool = true) -> some View {
        environment(\.disableHoverAnimation, disabled)
    }
}
