//
//  SettingsSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI

/// 设置的侧边栏。
///
/// 条目标题沿用 PCL2 的设置页：启动 / 个性化 / 其他。标题与页面不是一一对应的旧结构——
/// 「启动」继承原来的「游戏」页（Java 运行时与全局启动参数），「其他」继承原来的「启动器」页
/// （下载源、配置导出、调试、更新）；升级用户认的是内容，所以只换标题、不换页面。
///
/// 顺序按「影响面」排：先决定游戏怎么启动，再改外观，最后是启动器自身的行为。
struct SettingsSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 140

    let width: CGFloat = 140
    
    var body: some View {
        VStack {
            MyNavigationList(
                .init(.gameSettings, .iconLaunchPage, "启动"),
                .init(.personalizationSettings, .iconPersonalization, "个性化"),
                .init(.launcherSettings, .iconMorePage, "其他")
            )
            Spacer()
        }
        // 原版的条目列表从顶部 12pt 起排（MyPageLeft 里的 StackPanel Margin="0,12,0,0"）。
        .padding(.top, 12)
    }
}
