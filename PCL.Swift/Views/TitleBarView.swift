//
//  TitleBarView.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/10.
//

import SwiftUI
import Core

struct TitleBarView: View {
    /// 三色按钮占用的宽度：窗口左侧 20pt 起始 + 两个 14pt 按钮 + 间距 + 尾部留白。
    ///
    /// 缩放按钮是恒隐藏的（见 `AppWindow`），所以这里只给两个按钮留位。
    static let trafficLightReservedWidth: CGFloat = 62

    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var flagsManager: FlagsManager = .shared
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    /// 直接观察 ThemeManager：拖自定义滑杆时视图树不重建（revision 不动），
    /// 只有观察 palette 的视图才会实时换色。标题栏是用户最先看的地方，必须跟着变。
    @ObservedObject private var themeManager: ThemeManager = .shared
    
    var body: some View {
        ZStack(alignment: .leading) {
            NavigationBarBackgroundView()
            Group {
                if router.isSubPage {
                    HStack {
                        WindowButton(.btnBack) {
                            router.removeLast()
                        }
                        MyText(router.title, size: 16, color: .white)
                    }
                } else {
                    // 主页按钮组始终居中；Logo 的位置由设置决定（默认居左，
                    // 与 PCL 原版一致；选择居中时按钮组仍在原位，两者不重叠）。
                    HStack {
                        Spacer()
                        PageButton("启动", .iconLaunchPage, .launch)
                        PageButton("下载", .iconDownloadPage, .download)
                        if flagsManager.isEnabled(.multiplayer) {
                            PageButton("联机", .iconMultiplayerPage, .multiplayer)
                        }
                        PageButton("设置", .iconSettingsPage, .settings)
                        PageButton("更多", .iconMorePage, .more)
                        Spacer()
                    }

                    // 标识固定靠左：位置选项已移除，避免和居中的按钮组抢位置。
                    HStack {
                        logoView
                        Spacer()
                    }
                }
            }
            // 三色按钮由系统画在透明标题栏里（关闭 + 最小化，缩放按钮恒隐藏），
            // 内容从这里起排，留出按钮组占用的宽度，避免标题 Logo 压到按钮上。
            .padding(.leading, Self.trafficLightReservedWidth)
        }
        .frame(height: AppWindow.titleBarHeight)
    }

    /// 标题栏左侧的标识：默认 Logo、自定义文本或自定义图片。
    ///
    /// 三种形态共用同一块布局位置，切换时不会让右侧按钮组跳动。
    @ViewBuilder
    private var logoView: some View {
        switch LauncherConfig.shared.titleBarLogoType {
        case .none:
            EmptyView()
        case .logo:
            HStack(spacing: 4) {
                // 标题栏沿用 PCL 的白色线条字标（配合右侧的 "Swift" 标签读作 PCL.Swift）；
                // App 图标只用在开场动画里，不要挪到这里。
                Image(.iconTitleLogo)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(height: 19)
                MyTag("Swift", labelColor: .color2)

                if Metadata.debugMode {
                    MyTag("Debug", backgroundColor: Color(0x9BF00B))
                }
            }
        case .text:
            MyText(
                LauncherConfig.shared.titleBarText.isEmpty ? "PCL.Swift" : LauncherConfig.shared.titleBarText,
                size: 16,
                color: .white
            )
            .lineLimit(1)
        case .image:
            if let url = LauncherConfig.shared.titleBarImageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
            } else {
                Image(.iconTitleLogo)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(height: 19)
            }
        }
    }
}

private struct PageButton: View {
    @ObservedObject private var router: AppRouter = .shared
    @State private var hovered: Bool = false
    private var isRoot: Bool { router.root == route }
    private let label: String
    private let icon: ImageResource
    private let route: AppRoute
    
    init(_ label: String, _ icon: ImageResource, _ route: AppRoute) {
        self.label = label
        self.icon = icon
        self.route = route
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(backgroundColor)
            HStack(spacing: 7) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16)
                    .foregroundStyle(foregroundColor)
                MyText(label, color: foregroundColor)
            }
        }
        .frame(width: 78, height: 27)
        .contentShape(Rectangle())
        .onHover { hovered in
            self.hovered = hovered
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if router.root != route {
                        router.setRoot(route)
                    }
                }
        )
        // 顶栏页签对齐 PCL2 的 MyRadioButton（MyRadioBox 的常量）：
        // 鼠标进入 100ms、离开 200ms；选中态切换同样 100ms。
        .animation(hovered ? .easeOut(duration: 0.1) : .easeOut(duration: 0.2), value: hovered)
        .animation(.easeOut(duration: 0.1), value: isRoot)
    }
    
    private var foregroundColor: Color {
        isRoot ? .color2 : .white
    }
    
    private var backgroundColor: Color {
        .white.opacity(isRoot ? 1 : hovered ? 0.25 : 0)
    }
}
