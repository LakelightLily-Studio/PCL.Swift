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
/// 还没有实现的能力（CurseForge 源、文件名格式、Mod 管理样式、游戏更新提示）
/// 保留原版的行，但控件不可交互——放活的开关只会变成点了没反应。
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

    var body: some View {
        CardContainer {
            downloadCard
            communityCard
                .cardIndex(1)
            accessibilityCard
                .cardIndex(2)
            launcherCard
                .cardIndex(3)
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

    // MARK: - 社区资源（占位）

    private var communityCard: some View {
        MyCard("社区资源", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("来源", labelWidth: 120) {
                    placeholderText("尽量使用官方源")
                }
                SettingRow("文件名格式", labelWidth: 120) {
                    placeholderText("[译名] create-1.21.1-6.0.4")
                }
                SettingRow("Mod 管理样式", labelWidth: 120) {
                    placeholderText("标题显示译名，详情显示文件名")
                }
                MyTip(text: "占位：本启动器的资源下载目前只接入了 Modrinth，还没有 CurseForge 源、文件重命名与 Mod 译名，实现后这三行会换成真实控件。", theme: .yellow)
            }
        }
    }

    // MARK: - 辅助功能

    private var accessibilityCard: some View {
        MyCard("辅助功能", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("游戏更新提示", labelWidth: 120) {
                    MyComboBox(checked: .constant(false), text: "正式版更新提示")
                        .disabled(true)
                        .opacity(0.5)
                    MyComboBox(checked: .constant(false), text: "测试版更新提示")
                        .disabled(true)
                        .opacity(0.5)
                }
                SettingRow("游戏语言", labelWidth: 120) {
                    MyComboBox(checked: $autoSetGameLanguage, text: "自动设置为中文")
                        .onChange(of: autoSetGameLanguage) { newValue in
                            LauncherConfig.shared.autoSetGameLanguage = newValue
                            configObserver.touch()
                        }
                    Spacer(minLength: 0)
                }
                MyTip(text: "「自动设置为中文」只在实例还没有存档、或玩家没手动改过游戏语言时生效，不会覆盖你自己选的语言。「游戏更新提示」仍是占位：需要启动时比对版本列表，本启动器还没做。", theme: .blue)
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
