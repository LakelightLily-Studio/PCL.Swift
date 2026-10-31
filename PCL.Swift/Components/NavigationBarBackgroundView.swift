//
//  NavigationBarBackgroundView.swift
//  PCL.Swift
//
//  导航栏（标题栏）背景：纯色、主题色 + 白色线格，或液态玻璃。
//  向导顶栏和启动器顶栏共用，保证两处样式始终一致。
//

import SwiftUI

struct NavigationBarBackgroundView: View {
    @ObservedObject private var config: LauncherConfigObserver = .shared
    @ObservedObject private var themeManager: ThemeManager = .shared

    var body: some View {
        ZStack {
            switch LauncherConfig.shared.navigationBarBackground {
            case .theme:
                Color.color3
            case .lines:
                Color.color3
                InfiniteGrid(lineColor: .white.opacity(0.14), spacing: 24)
            case .liquidGlass:
                LiquidGlassView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
