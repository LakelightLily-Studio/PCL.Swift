//
//  AppRouter.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI
import Core

enum AppRoute: Identifiable, Hashable, Equatable {
    // 根页面
    case launch, download, multiplayer, settings, more, tasks
    
    // 启动页面的子页面
    case instanceList(repositoryId: UUID), instanceSettings(id: String)
    /// DSH 目录。与 Minecraft 仓库并列，但不参与 `versions/` 扫描。
    case dshInstanceList
    
    // 实例设置页面的子页面
    case instanceConfig(id: String), installedResources(id: String, type: ResourceType)
    /// 实例概览：改名、图标、描述、收藏、分类与各文件夹入口。
    case instanceOverview(id: String)
    /// 实例导出（整合包 / 启动脚本）。
    case instanceExport(id: String)
    
    // 下载页面的子页面
    case minecraftDownload, minecraftInstallOptions(version: VersionManifest.Version), modDownload, resourcepackDownload, shaderpackDownload, modpackDownload, datapackDownload
    case projectInstall(project: ProjectListItemModel)
    
    // 联机页面的子页面
    case multiplayerSub, multiplayerSettings
    
    // 设置页面的子页面
    case personalizationSettings, gameSettings, launcherSettings
    
    // 更多页面的子页面
    case about, toolbox
    
    var id: String { stringValue }
    
    var stringValue: String {
        switch self {
        default: String(describing: self)
        }
    }
}

@MainActor
class AppRouter: ObservableObject {
    static let shared: AppRouter = .init()
    
    @Published private(set) var path: [AppRoute] = [.launch]
    
    /// 当前子页面的标题
    var title: String {
        switch last {
        case .tasks: "任务列表"
        case .instanceList: "实例列表"
        case .dshInstanceList: "DSH"
        case .instanceSettings(let id), .instanceConfig(let id), .installedResources(let id, _),
             .instanceOverview(let id), .instanceExport(let id): "版本设置 - \(id)"
        case .minecraftInstallOptions(let version): "游戏安装 - \(version.id)"
        case .projectInstall(let project): "资源下载 - \(project.title)"
        default: "错误：当前页面（\(last)）没有标题，请报告此问题！"
        }
    }
    
    /// 当前页面是不是子页面（需要显示返回键和标题，隐藏导航按钮）
    var isSubPage: Bool {
        switch last {
        case .tasks: true
        case .instanceList: true
        case .dshInstanceList: true
        case .instanceSettings, .instanceConfig, .installedResources, .instanceOverview, .instanceExport: true
        case .minecraftInstallOptions: true
        case .projectInstall: true
        default: false
        }
    }
    
    var last: AppRoute { path[path.count - 1] }
    var root: AppRoute { path[0] }
    
    func setRoot(_ newRoot: AppRoute) {
        var newRoot: AppRoute = newRoot
        // 关掉联机开关后不允许再进入联机页：把路由请求改写回启动页，
        // 否则该开关只能隐藏入口，页面依旧可达。
        if !isRouteAvailable(newRoot) { newRoot = .launch }
        path = [newRoot]
        // 各根页面的默认子页面
        if newRoot == .download { append(.minecraftDownload) }
        if newRoot == .multiplayer { append(.multiplayerSub) }
        // 设置页的首个条目是「启动」（原「游戏」页），进入设置就落在它上面。
        if newRoot == .settings { append(.gameSettings) }
        if newRoot == .more { append(.about) }
    }
    
    func append(_ route: AppRoute) {
        guard isRouteAvailable(route) else { return }
        path.append(route)
        // 进入版本设置时先落在「概览」，与 PCL2 一致；设置页要自己点过去。
        if case .instanceSettings(let id) = route { append(.instanceOverview(id: id)) }
    }
    
    /// 在同一层级替换当前子页面（例如「Mod 管理」里切换资源类型）。
    ///
    /// 不能用 removeLast() + append：removeLast 在落到 instanceSettings 时会连着
    /// 把实例设置层也弹掉，结果换完类型就退回启动页了。
    func replaceLast(_ route: AppRoute) {
        guard path.count > 1 else {
            append(route)
            return
        }
        path.removeLast()
        append(route)
    }

    /// 返回上一级。
    ///
    /// 版本设置是「壳」层：从它的子页面返回时连它一起弹掉，直接回启动页。
    /// 这里先把最终路径算好再一次性赋值——早先是递归地改两次 `path`，
    /// 会发布两次变更，中间那一帧停在 `.instanceSettings` 上，标题栏因此
    /// 可能闪一下不该出现的中间态。
    func removeLast() {
        guard path.count > 1 else { return }
        var newPath: [AppRoute] = path
        newPath.removeLast()
        if let next = newPath.last, case .instanceSettings = next {
            newPath.removeLast()
        }
        path = newPath
    }
    
    /// 该路由在当前功能开关下是否可用。
    func isRouteAvailable(_ route: AppRoute) -> Bool {
        switch route {
        case .multiplayer, .multiplayerSub, .multiplayerSettings:
            return FlagsManager.shared.isEnabled(.multiplayer)
        default:
            return true
        }
    }

    /// 开关被关闭时，把停在联机页的会话退回启动页。
    func enforceFlagGates() {
        guard !isRouteAvailable(last) else { return }
        setRoot(.launch)
    }
    
    private init() {}
}

/// 内容区。
///
/// **按"页面族"常驻，族内切换用 switch**。
///
/// 全部页面常驻不现实（有的页面依赖运行期参数，例如不同实例的配置页），
/// 但把「每次切页都会重新构建」降到「只构建当前族」已经能去掉绝大部分开销：
///
/// - 设置族的三个子页共用同一批 @State，族内切换不必重建父级容器
/// - 更多族、下载族同理
/// - 带参数的页面（实例设置、安装选项）仍走 switch，它们本来就该按参数重建
///
/// 早期版本对整个 AppRouterView 套了 .id(router.last)，那会把整棵页面树
/// 连同 @StateObject 与 Combine 订阅一起销毁重建——这是切页 78ms 的主要来源。
struct AppRouterView: View {
    @ObservedObject private var router: AppRouter = .shared
    @ObservedObject private var transition: PageTransition = .shared
    @EnvironmentObject private var instanceManager: InstanceManager

    var body: some View {
        // 页面只认 PageTransition 的 presentation：退场期间挂着的仍是旧页面，
        // 退场跑完才换成新页面（PCL2 的 FormMain.PageChangeAnim 就是这个时序）。
        page(for: transition.presentation.route)
            // 退场期间整块内容不接收点击：PCL2 的 TriggerExitAnimation 会把
            // 每个控件 IsHitTestVisible 置 false，效果一致。
            .allowsHitTesting(!transition.presentation.isExiting)
            .environment(\.pageExiting, transition.presentation.isExiting)
            .onAppear { transition.sync() }
            .onChange(of: router.last) { newValue in
                transition.request(newValue)
            }
    }

    @ViewBuilder
    private func page(for route: AppRoute) -> some View {
        switch route {
        case .launch:
            LaunchPage()
        case .minecraftDownload:
            MinecraftDownloadPage()
        case .minecraftInstallOptions(let version):
            MinecraftInstallOptionsPage(instanceManager: instanceManager, version: version)
        case .modDownload:
            ResourcesSearchPage(type: .mod)
        case .resourcepackDownload:
            ResourcesSearchPage(type: .resourcepack)
        case .shaderpackDownload:
            ResourcesSearchPage(type: .shader)
        case .modpackDownload:
            ResourcesSearchPage(type: .modpack)
        case .datapackDownload:
            ResourcesSearchPage(type: .datapack)
        case .projectInstall(let project):
            ResourceInstallPage(instanceManager: instanceManager, project: project)
                .id(project)
        case .tasks:
            TasksPage()
        case .instanceList(let repositoryId):
            InstanceListPage(instanceManager: instanceManager, repositoryId: repositoryId)
                .id(repositoryId)
        case .dshInstanceList:
            DSHInstanceListPage()
        case .multiplayerSub:
            MultiplayerPage()
        case .multiplayerSettings:
            MultiplayerSettingsPage()
        case .personalizationSettings:
            PersonalizationSettingsPage()
        case .gameSettings:
            GameSettingsPage()
        case .launcherSettings:
            LauncherSettingsPage()
        case .about:
            AboutPage()
        case .toolbox:
            ToolboxPage()
        case .instanceConfig(let id):
            InstanceConfigPage(instanceManager: instanceManager, id: id)
                .id(id)
        case .installedResources(let id, let type):
            InstalledResourcesPage(instanceManager: instanceManager, id: id, type: type)
                .id("\(id)-\(type.rawValue)")
        case .instanceOverview(let id):
            InstanceOverviewPage(instanceManager: instanceManager, id: id)
                .id(id)
        case .instanceExport(let id):
            InstanceExportPage(instanceManager: instanceManager, id: id)
                .id(id)
        default:
            Spacer()
        }
    }
}

/// 侧边栏容器。
///
/// 用 @ViewBuilder 的 switch 按根页面切换侧边栏。
///
/// 曾试过让 9 个侧边栏全部常驻、只切 opacity：实测切页耗时没有下降，
/// 反而因为常驻节点数量翻倍，泛型元数据查找（MetadataCacheKey、
/// getGenericContext）的采样占比明显上升。SwiftUI 的切换成本主要来自
/// 构建新视图树，不是来自销毁旧的——所以"常驻"不解决问题，只是把
/// 成本从销毁挪到了每次布局。
struct AppSidebarView: View {
    @EnvironmentObject private var instanceManager: InstanceManager
    @ObservedObject private var transition: PageTransition = .shared
    @ObservedObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var backgroundImageManager: BackgroundImageManager = .shared
    @State private var width: CGFloat = 0
    /// 启动页 / 任务页侧边栏的"淡入 + 轻微放大"入场进度。
    @State private var animationProgress: Double = 0

    init() {}

    /// 当前挂着的页面。与 AppRouterView 共用同一条时间线：退场期间侧边栏也还是旧的。
    private var presentedRoute: AppRoute { transition.presentation.route }
    /// 侧边栏是否要播退场。
    ///
    /// 侧边栏条目发起的切换**不播**：那只是换个选中态，整列淡出再淡回来是多余的，
    /// 而且退场比换页窗口长，会被截断成"播一半突然复原"。
    /// 顶栏切页、返回按钮这些仍然照播。
    private var isExiting: Bool { transition.presentation.isExiting && !transition.isSidebarNavigation }

    /// 整块缩放退场的侧边栏。
    ///
    /// PCL2 的 MyPageLeft 按 XAML 里有没有 AnimatedControl 分两套退场：
    /// 启动页与任务页没有，走 110ms 缩到 0.95 + 80ms 淡出；其余侧边栏
    /// （下载 / 设置 / 更多 / 版本选择 / 版本设置）逐条目退场，见 MyNavigationList。
    private var usesScaleExit: Bool {
        switch presentedRoute {
        case .launch, .tasks: true
        default: false
        }
    }

    /// 侧边栏宽度。各侧边栏把宽度暴露为静态常量，避免为了取宽度去构造实例。
    private var sidebarWidth: CGFloat { width(for: presentedRoute) }

    private func width(for route: AppRoute) -> CGFloat {
        switch route {
        case .launch: LaunchSidebar.widthConstant
        case .instanceList, .dshInstanceList: InstanceListSidebar.widthConstant
        case .instanceSettings, .instanceConfig, .installedResources,
             .instanceOverview, .instanceExport: InstanceSettingsSidebar.widthConstant
        case .minecraftDownload, .modDownload, .resourcepackDownload, .shaderpackDownload,
             .modpackDownload, .datapackDownload: DownloadSidebar.widthConstant
        case .multiplayer, .multiplayerSub, .multiplayerSettings: MultiplayerSidebar.widthConstant
        case .settings, .personalizationSettings, .gameSettings, .launcherSettings: SettingsSidebar.widthConstant
        case .more, .about, .toolbox: MoreSidebar.widthConstant
        case .tasks: TasksSidebar.widthConstant
        default: EmptySidebar.widthConstant
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 有背景图片时底板换成 94% 白（PCL2 的 ColorBrushBackgroundTransparentSidebar），
            // 让图片能透出来；没有图片时仍是纯白。
            Rectangle()
                .fill(Color.white.opacity(backgroundImageManager.image == nil ? 1 : 0xF1 / 255))
                .frame(width: width)
                .shadow(radius: 2)
                .zIndex(10)

            sidebarContent(for: presentedRoute)
                .opacity(animationProgress)
                .scaleEffect(animationProgress * 0.04 + 0.96)
                // 整块退场：110ms 缩到 0.95（t²）+ 80ms 淡出（延迟 30ms），
                // 与 PCL2 的 MyPageLeft.TriggerHideAnimation 的缩放分支一致。
                .modifier(SidebarScaleExitShape(progress: isExiting ? 1 : 0, enabled: usesScaleExit))
                .animation(
                    usesScaleExit && isExiting ? .linear(duration: SidebarExit.scaleDuration) : nil,
                    value: isExiting
                )
                // 逐条目退场由 MyNavigationList 里的每个条目自己播。
                .environment(\.pageExiting, isExiting)
                .zIndex(11)
                .frame(width: sidebarWidth)
        }
        // 布局宽度必须一步到位：白色底板单独做宽度动画，容器宽度不跟着变，
        // 否则右侧页面会随收缩动画横移，卡片入场时看起来在漂。
        .frame(width: sidebarWidth, alignment: .leading)
        .onAppear {
            width = sidebarWidth
            if presentedRoute == .launch || presentedRoute == .tasks {
                playLegacyEntrance()
            } else {
                animationProgress = 1
            }
        }
        .onChange(of: sidebarWidth) { newWidth in
            withAnimation(.spring(response: 0.16, dampingFraction: 1.0)) {
                width = newWidth
            }
            // 只有启动页 / 任务页的侧边栏用这套淡入 + 放大；
            // 其它页面的入场在 MyNavigationList 里逐条目播放，两套不能同时挂。
            if presentedRoute == .launch || presentedRoute == .tasks {
                playLegacyEntrance()
            }
        }
    }

    /// 启动页 / 任务页侧边栏的入场动画（账户面板自己还有一层 insertTransition）。
    private func playLegacyEntrance() {
        guard !themeManager.isAdjustingCustomTheme else {
            animationProgress = 1
            return
        }
        animationProgress = 0
        // 下一帧再推到 1：同一次状态更新里 0 → 1 不会产生动画。
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                animationProgress = 1
            }
        }
    }

    @ViewBuilder
    private func sidebarContent(for route: AppRoute) -> some View {
        switch route {
        case .launch:
            LaunchSidebar(instanceManager: instanceManager)
        case .instanceList, .dshInstanceList:
            InstanceListSidebar(instanceManager: instanceManager)
        case .instanceSettings(let id), .instanceConfig(let id), .installedResources(let id, _),
             .instanceOverview(let id), .instanceExport(let id):
            InstanceSettingsSidebar(id: id)
        case .minecraftDownload, .modDownload, .resourcepackDownload, .shaderpackDownload,
             .modpackDownload, .datapackDownload:
            DownloadSidebar()
        case .multiplayer, .multiplayerSub, .multiplayerSettings:
            MultiplayerSidebar()
        case .settings, .personalizationSettings, .gameSettings, .launcherSettings:
            SettingsSidebar()
        case .more, .about, .toolbox:
            MoreSidebar()
        case .tasks:
            TasksSidebar()
        default:
            EmptySidebar()
        }
    }
}
