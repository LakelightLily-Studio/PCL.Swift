//
//  NavigationBarBackgroundView.swift
//  PCL.Swift
//
//  导航栏（标题栏）背景：纯色，或主题色 + 白色线格。
//  向导顶栏和启动器顶栏共用，保证两处样式始终一致。
//

import SwiftUI

struct NavigationBarBackgroundView: View {
    @ObservedObject private var config: LauncherConfigObserver = .shared
    @ObservedObject private var themeManager: ThemeManager = .shared

    var body: some View {
        ZStack {
            Color.color3
            if LauncherConfig.shared.navigationBarBackground == .lines {
                InfiniteGrid(lineColor: .white.opacity(0.14), spacing: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
