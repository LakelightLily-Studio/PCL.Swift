//
//  SettingsSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI

/// 设置的侧边栏。
///
/// 顺序按「影响面」排：个性化只改外观，游戏改游戏本身，启动器改启动器自身行为。
struct SettingsSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 140

    let width: CGFloat = 140
    
    var body: some View {
        VStack {
            MyNavigationList(
                .init(.personalizationSettings, .iconSun, "个性化"),
                .init(.gameSettings, .iconBlock, "游戏"),
                .init(.launcherSettings, .iconSettingsPage, "启动器")
            )
            Spacer()
        }
    }
}
