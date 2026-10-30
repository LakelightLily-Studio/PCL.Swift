//
//  MultiplayerSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/15.
//

import SwiftUI

struct MultiplayerSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 150

    let width: CGFloat = 150
    
    var body: some View {
        VStack {
            MyNavigationList(
                .init(.multiplayerSub, .iconMultiplayerPage, "联机"),
                .init(.multiplayerSettings, .iconSettingsPage, "设置")
            )
            Spacer()
        }
        .padding(.top, 12)
    }
}
