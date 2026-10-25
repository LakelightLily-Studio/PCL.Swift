//
//  InstanceSettingsSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI

struct InstanceSettingsSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 140

    let width: CGFloat = 140
    private let id: String
    
    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        VStack {
            MyNavigationList(
                .init(.instanceOverview(id: id), .iconBlock, "概览"),
                .init(.instanceConfig(id: id), .iconSettingsPage, "设置"),
                // 原版的资源包 / 光影包 / 数据包没有独立条目，都在「Mod 管理」里按类型切换。
                .init(.installedResources(id: id, type: .mod), .iconMod, "Mod 管理"),
                .init(.instanceExport(id: id), .iconUpload, "导出")
            )
            Spacer()
        }
    }
}
