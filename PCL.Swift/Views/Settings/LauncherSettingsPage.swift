//
//  LauncherSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/9.
//

import SwiftUI
import Core

/// 设置 → 其他。
///
/// 卡片与行序按 PCL2 的 PageSetupSystem 排：下载 / 社区资源 / 辅助功能 / 启动器。
/// 按要求不做「调试选项」整卡。
///
/// 还没有实现的能力（CurseForge 浏览源）保留原版的行，控件不可交互——
/// 放活的开关只会变成点了没反应。文件名格式与 Mod 管理样式已经做成真控件：
/// 前者由 Core 的 ResourceFileName 渲染到下载落点，后者控制实例里资源列表的标题。
struct LauncherSettingsPage: View {
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var downloadSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.downloadSourcePolicy
    @State private var versionListSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.versionListSourcePolicy
    /// 线程数与限速都走滑杆：与 PCL2 一致，取值映射见 DownloadSpeedLimit。
    @State private var threadCount: Double = Double(
        LauncherConfig.shared.downloadMaxThreads ?? DownloadSourceManager.shared.recommendedConcurrency
    )
    @State private var speedPosition: Double = Double(
        DownloadSpeedLimit.sliderPosition(forBytesPerSecond: Int64(LauncherConfig.shared.downloadSpeedLimit) * 1024)
    )
    @State private var updatePrompt: UpdatePromptMode = LauncherConfig.shared.ignoreLauncherUpdates ? .off : .notify
    @State private var autoSetGameLanguage: Bool = LauncherConfig.shared.autoSetGameLanguage
    /// 文件名格式与资源标题样式。改动即生效，落盘由 LauncherConfig 自己防抖。
    @State private var fileNameFormat: ResourceFileName.Format = LauncherConfig.shared.resourceFileNameFormat
    @State private var titleStyle: LauncherConfig.ResourceTitleStyle = LauncherConfig.shared.resourceTitleStyle
    /// 缓存设置：资源列表（开关 + 时间限制）与图标（开关，开启即落盘）。
    @State private var enableListCache: Bool = LauncherConfig.shared.enableResourceListCache
    @State private var listCacheMinutes: Int = LauncherConfig.shared.resourceListCacheMinutes
    @State private var enableImageCache: Bool = LauncherConfig.shared.enableImageCache

    var body: some View {
        CardContainer {
            downloadCard
            communityCard
                .cardIndex(1)
            cacheCard
                .cardIndex(2)
            accessibilityCard
                .cardIndex(3)
            launcherCard
                .cardIndex(4)
        }
        .onAppear {
            // 原版这一行就是独立的版本列表源。历史配置里可能是「跟随文件下载源」，
            // 那样界面上的下拉改了也不生效，所以进页面时一次性拆开并落盘。
            if !LauncherConfig.shared.separatesVersionListSource {
                LauncherConfig.shared.separatesVersionListSource = true
                DownloadSourceManager.shared.separatesVersionList = true
            }
        }
    }

    // MARK: - 下载

    private var downloadCard: some View {
        MyCard("下载", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("文件下载源", labelWidth: 120) {
                    MySelect($downloadSourcePolicy, entries: [.officialFirst, .mirrorFirst])
                        .frame(maxWidth: .infinity)
                        .onChange(of: downloadSourcePolicy) { newValue in
                            DownloadSourceManager.shared.policy = newValue
                            LauncherConfig.shared.downloadSourcePolicy = newValue
                        }
                }

                SettingRow("版本列表源", labelWidth: 120) {
                    MySelect($versionListSourcePolicy, entries: [.officialFirst, .mirrorFirst])
                        .frame(maxWidth: .infinity)
                        .onChange(of: versionListSourcePolicy) { newValue in
                            // 原版这一行就是独立下拉；本启动器原先有个「使用单独的下载源」
                            // 开关，选了这里就等价于把开关打开，不再保留那个开关。
                            LauncherConfig.shared.separatesVersionListSource = true
                            LauncherConfig.shared.versionListSourcePolicy = newValue
                            DownloadSourceManager.shared.separatesVersionList = true
                            DownloadSourceManager.shared.versionListSourcePolicy = newValue
                        }
                }

                SettingRow("最大线程数", labelWidth: 120) {
                    MySlider(
                        value: $threadCount,
                        range: 1...Double(DownloadSourceManager.concurrencyRange.upperBound),
                        step: 1
                    )
                    .onChange(of: threadCount) { newValue in
                        let value: Int = Int(newValue)
                        DownloadSourceManager.shared.setUserConcurrency(value)
                        LauncherConfig.shared.downloadMaxThreads = value
                    }
                    MyText("\(Int(threadCount)) 线程", size: 12, color: .colorGray3)
                        .frame(width: 64, alignment: .trailing)
                }

                SettingRow("速度限制", labelWidth: 120) {
                    MySlider(value: $speedPosition, range: 0...Double(DownloadSpeedLimit.maximumSliderPosition), step: 1)
                        .onChange(of: speedPosition) { newValue in
                            let bytes: Int64 = DownloadSpeedLimit.bytesPerSecond(forSliderPosition: Int(newValue))
                            DownloadSourceManager.shared.speedLimit = bytes
                            LauncherConfig.shared.downloadSpeedLimit = Int(bytes / 1024)
                        }
                    MyText(DownloadSpeedLimit.description(forSliderPosition: Int(speedPosition)), size: 12, color: .colorGray3)
                        .frame(width: 76, alignment: .trailing)
                }

                SettingRow("目标文件夹", labelWidth: 120, verticalPadding: 2) {
                    MyText("请在 启动 → 文件夹列表 中更改下载目标文件夹；在某个文件夹上右键即可打开对应目录。", size: 12, color: .colorGray3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - 社区资源

    private var communityCard: some View {
        MyCard("社区资源", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("来源", labelWidth: 140) {
                    placeholderText("尽量使用官方源")
                }
                SettingRow("文件名格式", labelWidth: 140) {
                    // 与原版一致：下拉框里直接是「译名 + 原始文件名」的示例，
                    // 选中哪一项就知道落盘会叫什么名字。
                    MySelect($fileNameFormat, entries: ResourceFileName.Format.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: fileNameFormat) { newValue in
                            LauncherConfig.shared.resourceFileNameFormat = newValue
                            configObserver.touch()
                        }
                }
                SettingRow("Mod 管理样式", labelWidth: 140) {
                    MySelect($titleStyle, entries: LauncherConfig.ResourceTitleStyle.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: titleStyle) { newValue in
                            LauncherConfig.shared.resourceTitleStyle = newValue
                            configObserver.touch()
                        }
                }
                MyText("文件名预览：" + fileNamePreview, size: 12, color: .colorGray3)
            }
        }
    }

    /// 拿一条真实项目渲染一次：格式的效果直接看得见，不用猜。
    private var fileNamePreview: String {
        ResourceFileName.format(
            format: fileNameFormat,
            name: "机械动力",
            originalName: "create-1.21.1-6.0.4.jar",
            type: .mod
        )
    }

    // MARK: - 缓存

    private var cacheCard: some View {
        MyCard("缓存", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("资源列表", labelWidth: 120) {
                    MyComboBox(checked: $enableListCache, text: "启用资源列表缓存")
                        .onChange(of: enableListCache) { newValue in
                            LauncherConfig.shared.enableResourceListCache = newValue
                            // 关掉时立刻清空，避免"关了还在用旧数据"。
                            if !newValue {
                                ResourceCacheCenter.shared.clearLists()
                            }
                            configObserver.touch()
                        }
                }

                SettingRow("时间限制", labelWidth: 120) {
                    // 不要在这里再补 Spacer：SettingRow 的内容区本来就靠右对齐，
                    // 多一个尾部 Spacer 会把下拉框顶回左边，与上下两行的复选框错开。
                    MySelect($listCacheMinutes, entries: [10, 30])
                        .frame(width: 140)
                        .disabled(!enableListCache)
                        .opacity(enableListCache ? 1 : 0.5)
                        .onChange(of: listCacheMinutes) { newValue in
                            LauncherConfig.shared.resourceListCacheMinutes = newValue
                            configObserver.touch()
                        }
                    MyText("分钟", size: 12, color: .colorGray3)
                }

                SettingRow("图标", labelWidth: 120) {
                    MyComboBox(checked: $enableImageCache, text: "启用图标缓存")
                        .onChange(of: enableImageCache) { newValue in
                            LauncherConfig.shared.enableImageCache = newValue
                            // 「关了就没缓存」：内存与磁盘一起清掉。
                            if !newValue {
                                ResourceCacheCenter.shared.clearImages()
                                InstanceIconStore.shared.clearMemory()
                            }
                            configObserver.touch()
                        }
                }

                SettingRow("缓存管理", labelWidth: 120) {
                    MyButton("清除缓存") { confirmClearCache() }
                        .frame(width: 120)
                }

                MyText(
                    "资源列表缓存：搜索结果与已安装模组列表会缓存在内存里，翻页、切子页面、重复搜索同一条件时"
                    + "不再重新加载，超过时间限制后自动失效。\n"
                    + "图标缓存：资源图标会写入缓存目录，下次打开不必重新下载；关掉后每次都从网络获取。",
                    size: 12,
                    color: .colorGray3
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 清除缓存：内存与磁盘一起清，实例图标的缩略图内存层也一起清掉。
    private func confirmClearCache() {
        MessageBoxManager.shared.showText(
            title: "清除缓存",
            content: "将清空资源列表缓存与图标缓存（内存与磁盘都会清掉），下次打开会重新从网络获取。\n此操作不可撤销，是否继续？",
            level: .info,
            .no(),
            .yes()
        ) { button in
            guard button == 1 else { return }
            ResourceCacheCenter.shared.clearLists()
            ResourceCacheCenter.shared.clearImages()
            InstanceIconStore.shared.clearMemory()
            hint("缓存已清除！", type: .finish)
        }
    }

    // MARK: - 辅助功能

    private var accessibilityCard: some View {
        MyCard("辅助功能", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("游戏语言", labelWidth: 120) {
                    // 不要再跟一个 Spacer：SettingRow 的内容区自带前置 Spacer 做右对齐，
                    // 行内多一个 Spacer 会把复选框顶回左边，和别的行错开（图 3 的问题）。
                    MyComboBox(checked: $autoSetGameLanguage, text: "自动设置为中文")
                        .onChange(of: autoSetGameLanguage) { newValue in
                            LauncherConfig.shared.autoSetGameLanguage = newValue
                            configObserver.touch()
                        }
                }
                MyTip(text: "「自动设置为中文」只在实例还没有存档、或玩家没手动改过游戏语言时生效，不会覆盖你自己选的语言。", theme: .blue)
            }
        }
    }

    // MARK: - 启动器

    private var launcherCard: some View {
        MyCard("启动器", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("启动器更新", labelWidth: 120) {
                    MySelect($updatePrompt, entries: UpdatePromptMode.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: updatePrompt) { newValue in
                            LauncherConfig.shared.ignoreLauncherUpdates = newValue == .off
                            configObserver.touch()
                        }
                }

                HStack(spacing: 20) {
                    MyButton("检查更新") {
                        UpdateService.shared.runInteractiveUpdateFlow(manually: true)
                    }
                    .frame(width: 120)
                    MyButton("导出设置") { exportSettings() }
                        .frame(width: 120)
                    MyButton("导入设置") { importSettings() }
                        .frame(width: 120)
                    Spacer()
                }
                .frame(height: 35)
                .padding(.top, 4)
            }
        }
    }

    private func exportSettings() {
        let panel: NSSavePanel = .init()
        panel.title = "导出启动器设置"
        panel.nameFieldStringValue = "pcl-swift-settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let data: Data = try SettingsTransferService.exportData(from: LauncherConfig.shared)
                try data.write(to: url)
                hint("设置导出成功！", type: .finish)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                err("导出设置失败：\(error.localizedDescription)")
                hint("导出设置失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func importSettings() {
        let panel: NSOpenPanel = .init()
        panel.title = "导入启动器设置"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            MessageBoxManager.shared.showText(
                title: "确认导入",
                content: "导入会覆盖当前的外观、下载与启动默认值设置。\n账号、目录与实例列表不会受影响。\n\n是否继续？",
                level: .info,
                .no(),
                .yes(type: .highlight)
            ) { button in
                guard button == 1 else { return }
                do {
                    let data: Data = try Data(contentsOf: url)
                    let applied: Int = try SettingsTransferService.importData(data, into: .shared)
                    guard applied > 0 else {
                        hint("这个文件里没有任何可导入的设置项。", type: .critical)
                        return
                    }
                    // 导入后同步到各消费点：下载源策略与功能开关都有各自的运行时副本。
                    DownloadSourceManager.shared.policy = LauncherConfig.shared.downloadSourcePolicy
                    DownloadSourceManager.shared.separatesVersionList = LauncherConfig.shared.separatesVersionListSource
                    DownloadSourceManager.shared.versionListSourcePolicy = LauncherConfig.shared.versionListSourcePolicy
                    DownloadSourceManager.shared.setUserConcurrency(LauncherConfig.shared.downloadMaxThreads)
                    DownloadSourceManager.shared.speedLimit = Int64(LauncherConfig.shared.downloadSpeedLimit) * 1024
                    threadCount = Double(LauncherConfig.shared.downloadMaxThreads ?? DownloadSourceManager.shared.recommendedConcurrency)
                    speedPosition = Double(DownloadSpeedLimit.sliderPosition(forBytesPerSecond: Int64(LauncherConfig.shared.downloadSpeedLimit) * 1024))
                    autoSetGameLanguage = LauncherConfig.shared.autoSetGameLanguage
                    if let flags = LauncherConfig.shared.enabledFlags {
                        for flag in FeatureFlag.allCases {
                            FlagsManager.shared.setEnabled(flag, enabled: flags.contains(flag))
                        }
                    }
                    ThemeManager.shared.set(LauncherConfig.shared.theme)
                    configObserver.touch()
                    hint("已导入 \(applied) 项设置！部分更改需要重启启动器才会完全生效。", type: .finish)
                } catch {
                    err("导入设置失败：\(error.localizedDescription)")
                    hint("导入设置失败：\(error.localizedDescription)", type: .critical)
                }
            }
        }
    }

    // MARK: - 占位

    /// 占位行：保留原版的名称与示例值，但不可交互。
    private func placeholderText(_ sample: String) -> some View {
        MyText(sample, size: 12, color: .colorGray3)
    }

    // MARK: - 更新提示

    /// 「启动器更新」这一行的取值。原版有四个选项（自动下载 / 提示 / 仅重大漏洞提示 / 关闭），
    /// 本启动器只有「提示」与「关闭」两种真实行为，所以只暴露这两项。
    enum UpdatePromptMode: String, CaseIterable, CustomStringConvertible {
        case notify, off

        var description: String {
            switch self {
            case .notify: "在有新版本时显示提示"
            case .off: "关闭更新提示"
            }
        }
    }
}
