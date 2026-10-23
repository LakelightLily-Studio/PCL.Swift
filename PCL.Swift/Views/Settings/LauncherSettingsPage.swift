//
//  LauncherSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/9.
//

import SwiftUI
import Core

/// 设置 → 启动器。
///
/// 原先这里是「下载 + 个性化」，「其它」页则是「调试 + 启动器更新」。
/// 现在个性化搬去了独立页（PersonalizationSettingsPage），其余两页合并成一页：
/// 它们描述的都是启动器自身的行为（怎么下载、导不导出日志、要不要检查更新）。
struct LauncherSettingsPage: View {
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var downloadSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.downloadSourcePolicy
    @State private var versionListSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.versionListSourcePolicy
    @State private var maxThreads: String = LauncherConfig.shared.downloadMaxThreads.map(String.init) ?? ""
    @State private var speedLimit: String = String(LauncherConfig.shared.downloadSpeedLimit)

    var body: some View {
        CardContainer {
            downloadCard
            configFileCard
                .cardIndex(1)
            debugCard
                .cardIndex(2)
            updateCard
                .cardIndex(3)
        }
    }

    // MARK: - 下载

    private var downloadCard: some View {
        MyCard("下载", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                configLine(label: "下载源") {
                    MySelect(
                        $downloadSourcePolicy,
                        entries: [.officialFirst, .mirrorFirst]
                    )
                    .frame(width: 180)
                }
                .onChange(of: downloadSourcePolicy) { newValue in
                    DownloadSourceManager.shared.policy = newValue
                    LauncherConfig.shared.downloadSourcePolicy = newValue
                }

                SettingRow("版本列表源", labelWidth: 120) {
                    VStack(alignment: .leading, spacing: 8) {
                        MyComboBox(checked: Binding(
                            get: { LauncherConfig.shared.separatesVersionListSource },
                            set: { enabled in
                                LauncherConfig.shared.separatesVersionListSource = enabled
                                DownloadSourceManager.shared.separatesVersionList = enabled
                                configObserver.touch()
                            }
                        ), text: "版本列表使用单独的下载源")
                        if LauncherConfig.shared.separatesVersionListSource {
                            MySelect($versionListSourcePolicy, entries: [.officialFirst, .mirrorFirst])
                                .frame(width: 180)
                                .onChange(of: versionListSourcePolicy) { newValue in
                                    LauncherConfig.shared.versionListSourcePolicy = newValue
                                    DownloadSourceManager.shared.versionListSourcePolicy = newValue
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                configLine(label: "最大并发数") {
                    MyTextField(text: $maxThreads, placeholder: "留空则跟随下载源推荐值")
                        .frame(width: 200)
                        .onChange(of: maxThreads) { newValue in
                            applyMaxThreads(newValue)
                        }
                    MyButton("恢复默认") {
                        maxThreads = ""
                        DownloadSourceManager.shared.setUserConcurrency(nil)
                        LauncherConfig.shared.downloadMaxThreads = nil
                    }
                    .frame(width: 90)
                    MyText("当前：\(DownloadSourceManager.shared.recommendedConcurrency)", size: 12, color: .colorGray3)
                }

                configLine(label: "下载限速") {
                    MyTextField(text: $speedLimit, placeholder: "0 表示不限速")
                        .frame(width: 120)
                        .onChange(of: speedLimit) { newValue in
                            applySpeedLimit(newValue)
                        }
                    MyText("KB/s", size: 12, color: .colorGray3)
                }

                configLine(label: "缓存目录") {
                    MyText(cacheDirectoryDescription, size: 12, color: .colorGray2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    MyButton("更改") { chooseCacheDirectory() }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 80)
                    MyButton("恢复默认") {
                        LauncherConfig.shared.customCacheDirectory = nil
                        configObserver.touch()
                        hint("缓存目录已恢复默认，重启后生效！", type: .finish)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 100)
                    .disabled(LauncherConfig.shared.customCacheDirectory == nil)
                }

                MyTip(text: "并发数与限速只影响后续下载，正在执行的任务不会重新分片。缓存目录的更改需要重启启动器才会生效。", theme: .blue)
            }
        }
    }

    private var cacheDirectoryDescription: String {
        LauncherConfig.shared.customCacheDirectory?.path ?? URLConstants.cacheURL.path + "（默认）"
    }

    private func applyMaxThreads(_ text: String) {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DownloadSourceManager.shared.setUserConcurrency(nil)
            LauncherConfig.shared.downloadMaxThreads = nil
            return
        }
        guard let value = Int(trimmed) else { return }
        let range: ClosedRange<Int> = DownloadSourceManager.concurrencyRange
        let clamped: Int = min(max(value, range.lowerBound), range.upperBound)
        if clamped != value {
            // 输入被夹紧时回写，否则界面显示的数字与实际生效值不一致。
            maxThreads = String(clamped)
        }
        DownloadSourceManager.shared.setUserConcurrency(clamped)
        LauncherConfig.shared.downloadMaxThreads = clamped
    }

    private func applySpeedLimit(_ text: String) {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Int = max(0, Int(trimmed) ?? 0)
        LauncherConfig.shared.downloadSpeedLimit = value
        DownloadSourceManager.shared.speedLimit = Int64(value) * 1024
    }

    private func chooseCacheDirectory() {
        let panel: NSOpenPanel = .init()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "选择缓存目录"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            LauncherConfig.shared.customCacheDirectory = url
            configObserver.touch()
            hint("缓存目录已更改，重启后生效！", type: .finish)
        }
    }

    // MARK: - 配置文件

    private var configFileCard: some View {
        StaticCard("配置文件") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 15) {
                    MyButton("导出设置") { exportSettings() }
                        .frame(width: 120)
                    MyButton("导入设置") { importSettings() }
                        .frame(width: 120)
                    Spacer()
                }
                .frame(height: 35)
                MyTip(text: "导出的文件只包含外观、下载与启动默认值，不包含账号与目录信息。导入会覆盖当前这些设置，账号不受影响。", theme: .yellow)
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

    // MARK: - 调试

    private var debugCard: some View {
        MyCard("调试", foldable: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MyButton("导出日志") {
                        do {
                            let url: URL = try SettingsViewModel.shared.exportLogs()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            err("导出日志失败：\(error.localizedDescription)")
                            hint("导出日志失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 40)

                Text("功能开关")
                    .foregroundStyle(Color.color1)
                    .font(.custom("PingFangSC-Semibold", size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)

                MyTip(text: "以下开关用于控制实验性功能及未经充分验证的更改。除非你了解其影响，否则请不要更改它们！", theme: .yellow)

                VStack(alignment: .leading) {
                    MyComboBox(checked: binding(of: .deduplicateLibraries), text: "去除同一清单中的重复依赖库")
                    MyComboBox(checked: binding(of: .multiplayer), text: "联机功能")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 更新

    private var updateCard: some View {
        StaticCard("启动器更新") {
            HStack {
                MyButton("检查更新") {
                    UpdateService.shared.runInteractiveUpdateFlow(manually: true)
                }
                .frame(width: 150)
                Spacer()
            }
            .frame(height: 40)
        }
    }

    // MARK: - 组件

    @ViewBuilder
    private func configLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, labelWidth: 120, content: body)
    }

    private func binding(of flag: FeatureFlag) -> Binding<Bool> {
        return .init(
            get: { FlagsManager.shared.isEnabled(flag) },
            set: { FlagsManager.shared.setEnabled(flag, enabled: $0) }
        )
    }
}
