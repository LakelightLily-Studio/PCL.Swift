//
//  DownloadSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/10.
//

import SwiftUI
import Core

struct DownloadSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 150

    @EnvironmentObject private var minecraftDownloadPageViewModel: MinecraftDownloadPageViewModel
    
    let width: CGFloat = 150
    
    /// 入场 / 退场错峰按整列算：2 个灰色小标题 + 6 个条目。
    /// PCL2 的 MyPageLeft 把标题和条目放在同一个 StackPanel 里统一编号，标题也参与动画。
    private static let controlCount: Int = 8

    var body: some View {
        VStack(spacing: 4) {
            SidebarSectionTitle("Minecraft", index: 0, exitCount: Self.controlCount)
                .padding(.top, 10)
            MyNavigationList(
                routeList: [.init(.minecraftDownload, .iconVanillaGame, "游戏下载")],
                indexOffset: 1,
                exitCount: Self.controlCount
            ) { route in
                switch route {
                case .minecraftDownload:
                    minecraftDownloadPageViewModel.reload()
                default: break
                }
            }
            
            SidebarSectionTitle("社区资源", index: 2, exitCount: Self.controlCount)
                .padding(.top, 20)
            // 每个条目都挂刷新（原版 PageDownloadLeft 的 6 个条目各有一个「刷新」按钮）：
            // 侧边栏与页面不在同一棵视图树里，这里只发一个按类型计数的信号，
            // 由对应的资源页自己用当前筛选条件重新搜索。
            MyNavigationList(
                routeList: [
                    .init(.modDownload, .iconMod, "Mod"),
                    .init(.resourcepackDownload, .iconPicture, "资源包"),
                    .init(.shaderpackDownload, .iconSun, "光影包"),
                    .init(.modpackDownload, .iconBox, "整合包"),
                    .init(.datapackDownload, .iconDataPack, "数据包"),
                ],
                indexOffset: 3,
                exitCount: Self.controlCount
            ) { route in
                guard let type: ResourceType = route.resourceType else { return }
                ResourceRefreshCenter.shared.request(type)
            }
            Spacer()
        }
    }
}

private extension AppRoute {
    /// 下载页路由对应的资源类型。
    var resourceType: ResourceType? {
        switch self {
        case .modDownload: .mod
        case .resourcepackDownload: .resourcepack
        case .shaderpackDownload: .shader
        case .modpackDownload: .modpack
        case .datapackDownload: .datapack
        default: nil
        }
    }
}
