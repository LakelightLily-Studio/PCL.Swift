//
//  MoreSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/7.
//

import SwiftUI

struct MoreSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 140

    let width: CGFloat = 140
    
    var body: some View {
        VStack {
            MyNavigationList(
                .init(.about, .iconAbout, "关于与鸣谢"),
                .init(.toolbox, .iconBox, "百宝箱")
            )
            Spacer()
        }
        .padding(.top, 12)
    }
}
