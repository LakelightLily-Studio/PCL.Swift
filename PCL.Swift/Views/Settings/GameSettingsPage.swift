//
//  GameSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI
import Core

/// 设置 → 游戏。
///
/// Java 运行时管理原先独占一个侧边栏条目（「Java 管理」），现在归到游戏页下：
/// Java 只服务于启动游戏，当作游戏配置比当作启动器的全局配置更贴合语义。
///
/// 这里同时放"全局默认启动设置"：实例页里那些标了「跟随全局」的项，
/// 值就来自这一页。两处必须成对存在，否则用户改不到默认值。
struct GameSettingsPage: View {
    @StateObject private var viewModel: JavaSettingsViewModel = .init()
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared

    @State private var windowType: GameWindowType = LauncherConfig.shared.gameWindowType
    @State private var windowTitle: String = LauncherConfig.shared.gameWindowTitle
    @State private var windowWidth: String = String(LauncherConfig.shared.gameWindowWidth)
    @State private var windowHeight: String = String(LauncherConfig.shared.gameWindowHeight)
    @State private var launcherVisibility: LauncherVisibility = LauncherConfig.shared.launcherVisibility
    @State private var processPriority: ProcessPriority = LauncherConfig.shared.processPriority
    @State private var prelaunchCommand: String = LauncherConfig.shared.prelaunchCommand
    @State private var prelaunchWait: Bool = LauncherConfig.shared.prelaunchWaitForCompletion
    @State private var gameArguments: String = LauncherConfig.shared.gameArguments
    @State private var jvmArguments: String = LauncherConfig.shared.jvmArguments
    @State private var memory: String = String(LauncherConfig.shared.memory)
    @State private var memoryOptimize: Bool = LauncherConfig.shared.memoryOptimize

    var body: some View {
        CardContainer {
            javaButtonsCard
            javaListCard
                .cardIndex(1)
            launchDefaultsCard
                .cardIndex(2)
        }
    }

    // MARK: - Java

    private var javaButtonsCard: some View {
        MyCard(nil) {
            HStack {
                MyButton("刷新 Java 列表") {
                    do {
                        try JavaManager.shared.research()
                        hint("刷新成功！", type: .finish)
                    } catch {
                        err("刷新 Java 列表失败：\(error.localizedDescription)")
                        hint("刷新 Java 列表失败：\(error.localizedDescription)", type: .critical)
                    }
                }
                .frame(width: 120)

                MyButton("安装 Java") {
                    Task {
                        do {
                            let downloads: [MojangJavaList.JavaDownload] = try await viewModel.javaDownloads()
                            if let index: Int = await MessageBoxManager.shared.showListAsync(
                                title: "选择 Java 版本",
                                items: downloads.map(viewModel.listItem(forJavaDownload:))
                            ) {
                                TaskManager.shared.execute(task: JavaInstallTask.create(download: downloads[index]))
                                AppRouter.shared.append(.tasks)
                            }
                        } catch {
                            err("拉取 Java 列表失败：\(error.localizedDescription)")
                            hint("拉取 Java 列表失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                }
                .frame(width: 120)

                MyButton("手动添加 Java") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.title = "选择 java 可执行文件"

                    panel.begin { result in
                        guard result == .OK, let url = panel.url else { return }
                        do {
                            let runtime = try viewModel.addCustomRuntime(at: url)
                            hint("添加 \(runtime.description) 成功！", type: .finish)
                        } catch {
                            hint("添加 Java 失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                }
                .frame(width: 120)

                Spacer()
            }
            .frame(height: 40)
        }
    }

    private var javaListCard: some View {
        MyCard("Java 列表", folded: false) {
            VStack(spacing: 0) {
                ForEach(0..<viewModel.javaList.count, id: \.self) { idx in
                    let item = viewModel.javaList[idx]
                    MyListItem { hovered in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                MyText(item.name)
                                    .lineLimit(1)
                                MyText(item.url.path, color: .colorGray3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if item.isCustom && hovered {
                                Image(systemName: "trash")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 12)
                                    .foregroundStyle(Color.color3)
                                    .padding(.trailing, 8)
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        viewModel.removeCustomRuntime(at: item.url)
                                        hint("移除成功！", type: .finish)
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 启动默认值

    private var launchDefaultsCard: some View {
        StaticCard("默认启动设置") {
            VStack(alignment: .leading, spacing: 10) {
                MyTip(text: "这些是全局默认值。实例设置里勾选「跟随全局」的项会使用这里的值。", theme: .blue)

                SettingRow("窗口标题", labelWidth: 120) {
                    MyTextField(text: $windowTitle, placeholder: "留空则使用游戏自身标题")
                        .onChange(of: windowTitle) { LauncherConfig.shared.gameWindowTitle = $0 }
                    if !GameWindowTitle.isTrusted {
                        MyButton("授权") {
                            GameWindowTitle.requestPermission()
                            hint("请在「系统设置 → 隐私与安全性 → 辅助功能」中允许 PCL.Swift，然后重启启动器。", type: .info)
                        }
                        .frame(width: 80)
                    }
                }
                if !GameWindowTitle.isTrusted {
                    MyTip(text: "修改游戏窗口标题需要「辅助功能」权限。未授权时这个设置不会生效，游戏会显示自己的默认标题。", theme: .yellow)
                }
                SettingRow("窗口模式", labelWidth: 120) {
                    MySelect($windowType, entries: GameWindowType.allCases)
                        .frame(width: 150)
                        .onChange(of: windowType) { LauncherConfig.shared.gameWindowType = $0 }
                }
                if windowType == .custom {
                    SettingRow("窗口大小", labelWidth: 120) {
                        MyTextField(text: $windowWidth)
                            .frame(width: 80)
                            .onChange(of: windowWidth) { newValue in
                                if let value = Int(newValue) { LauncherConfig.shared.gameWindowWidth = value }
                            }
                        MyText("×")
                        MyTextField(text: $windowHeight)
                            .frame(width: 80)
                            .onChange(of: windowHeight) { newValue in
                                if let value = Int(newValue) { LauncherConfig.shared.gameWindowHeight = value }
                            }
                    }
                }
                SettingRow("启动器可见性", labelWidth: 120) {
                    MySelect($launcherVisibility, entries: LauncherVisibility.allCases)
                        .frame(width: 200)
                        .onChange(of: launcherVisibility) { LauncherConfig.shared.launcherVisibility = $0 }
                }
                SettingRow("进程优先级", labelWidth: 120) {
                    MySelect($processPriority, entries: ProcessPriority.allCases)
                        .frame(width: 120)
                        .onChange(of: processPriority) { LauncherConfig.shared.processPriority = $0 }
                }
                SettingRow("启动前执行命令", labelWidth: 120) {
                    MyTextField(text: $prelaunchCommand, placeholder: "例如 open -a CleanMyMac")
                        .onChange(of: prelaunchCommand) { LauncherConfig.shared.prelaunchCommand = $0 }
                }
                SettingRow("等待命令完成", labelWidth: 120) {
                    MyComboBox(checked: $prelaunchWait, text: "命令执行完成后才继续启动")
                        .onChange(of: prelaunchWait) { LauncherConfig.shared.prelaunchWaitForCompletion = $0 }
                    Spacer(minLength: 0)
                }
                SettingRow("内存优化", labelWidth: 120) {
                    MyComboBox(checked: $memoryOptimize, text: "启动游戏前进行内存优化")
                        .onChange(of: memoryOptimize) { LauncherConfig.shared.memoryOptimize = $0 }
                    Spacer(minLength: 0)
                }
                SettingRow("默认内存", labelWidth: 120) {
                    MyTextField(text: $memory)
                        .frame(width: 120)
                        .onChange(of: memory) { newValue in
                            if let value = UInt64(newValue) { LauncherConfig.shared.memory = value }
                        }
                    MyText("MB", size: 12, color: .colorGray3)
                }
                SettingRow("附加游戏参数", labelWidth: 120) {
                    MyTextField(text: $gameArguments, placeholder: "例如 --server example.com")
                        .onChange(of: gameArguments) { LauncherConfig.shared.gameArguments = $0 }
                }
                SettingRow("额外 JVM 参数", labelWidth: 120) {
                    MyTextField(text: $jvmArguments, placeholder: "例如 -XX:+UseG1GC")
                        .onChange(of: jvmArguments) { LauncherConfig.shared.jvmArguments = $0 }
                }

                MyTip(text: "窗口相关的 --width / --height / --fullscreen 由「窗口模式」接管，在参数里重复填写不会生效。", theme: .yellow)
            }
        }
    }
}
