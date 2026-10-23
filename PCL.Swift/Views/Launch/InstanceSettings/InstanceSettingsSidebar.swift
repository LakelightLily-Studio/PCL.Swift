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
                .init(.instanceConfig(id: id), .iconSettingsPage, "配置"),
                .init(.installedResources(id: id, type: .mod), .iconMod, "Mod 管理"),
                .init(.installedResources(id: id, type: .resourcepack), .iconPicture, "资源包"),
                .init(.installedResources(id: id, type: .shader), .iconSun, "光影包"),
                .init(.installedResources(id: id, type: .datapack), .iconBox, "数据包"),
                .init(.instanceExport(id: id), .iconUpload, "导出")
            )
            Spacer()
        }
    }
}
