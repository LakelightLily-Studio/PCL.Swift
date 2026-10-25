//
//  GameSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI
import Foundation
import Core

/// 设置 → 启动。
///
/// 排版对齐 PCL2 的 PageSetupLaunch：启动选项 / 内存分配 / 高级选项，末尾是
/// 「版本独立设置」的入口。标题沿用 PCL2 的叫法，所以「启动」这一页里既有
/// 游戏侧的启动参数，也有 Java 与垃圾回收器。
///
/// 与 PCL2 的差异只有三类，都是平台原因，不是偷懒：
/// - 「离线皮肤」整卡不做：本启动器没有皮肤注入通道；
/// - 高级选项里的 Java Launch Wrapper / LWJGL Unsafe Agent / 使用高性能显卡
///   是 Windows 专用补丁，macOS 上没有对应物；
/// - 「启动前进行内存优化」调用的是 Windows 的 EmptyWorkingSet，macOS 没有等价物；
///   强制回收（purge）需要管理员权限，不适合塞进启动流程。
///
/// Java 运行时管理原来独占两张卡，现在按 PCL2 的位置并进「高级选项」。
struct GameSettingsPage: View {
    @StateObject private var viewModel: JavaSettingsViewModel = .init()
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared

    // 启动选项
    @State private var windowType: GameWindowType = LauncherConfig.shared.gameWindowType
    @State private var windowWidth: String = String(LauncherConfig.shared.gameWindowWidth)
    @State private var windowHeight: String = String(LauncherConfig.shared.gameWindowHeight)
    @State private var launcherVisibility: LauncherVisibility = LauncherConfig.shared.launcherVisibility
    @State private var processPriority: ProcessPriority = LauncherConfig.shared.processPriority

    // 内存分配
    @State private var memoryMode: MemoryAllocationMode = LauncherConfig.shared.memoryMode
    @State private var memorySlider: Double = Double(
        MemoryAllocation.sliderPosition(forGigabytes: Double(LauncherConfig.shared.memory) / 1024)
    )
    /// 自动配置的推荐值与内存条读数都在进页面时算一次。
    /// 放进 body 会在每次布局时各做一次 syscall（host_statistics64），没必要。
    @State private var automaticMemoryGB: Double = MemoryAllocation.recommendedGigabytes()
    @State private var usedMemoryGB: Double = Double(MemoryAllocation.usedBytes) / 1_073_741_824
    @State private var totalMemoryGB: Double = Double(MemoryAllocation.physicalBytes) / 1_073_741_824

    // 高级选项
    @State private var jvmArguments: String = LauncherConfig.shared.jvmArguments
    @State private var gameArguments: String = LauncherConfig.shared.gameArguments
    @State private var prelaunchCommand: String = LauncherConfig.shared.prelaunchCommand
    @State private var garbageCollector: GarbageCollectorMode = LauncherConfig.shared.garbageCollector
    /// 「还原 JVM 参数」小图标的悬停高亮。
    @State private var resetHovered: Bool = false

    var body: some View {
        CardContainer {
            launchOptionsCard
            memoryCard
                .cardIndex(1)
            advancedCard
                .cardIndex(2)
        }
        .onAppear(perform: refreshMemoryReadings)
    }

    // MARK: - 启动选项

    private var launchOptionsCard: some View {
        MyCard("启动选项", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                // 下拉框一律吃满整行：PCL2 的「设置」是两列网格（名称列 Auto、
                // 控件列 1*），右边缘必须完全对齐，不能各自定宽。
                SettingRow("启动器可见性", labelWidth: 120) {
                    MySelect($launcherVisibility, entries: LauncherVisibility.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: launcherVisibility) { LauncherConfig.shared.launcherVisibility = $0 }
                }
                SettingRow("进程优先级", labelWidth: 120) {
                    MySelect($processPriority, entries: ProcessPriority.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: processPriority) { LauncherConfig.shared.processPriority = $0 }
                }
                SettingRow("窗口大小", labelWidth: 120) {
                    MySelect($windowType, entries: GameWindowType.allCases)
                        .frame(maxWidth: .infinity)
                        .onChange(of: windowType) { LauncherConfig.shared.gameWindowType = $0 }
                    if windowType == .custom {
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
                MyTip(text: "窗口相关的 --width / --height / --fullscreen 由这里接管，在「游戏参数」里重复填写不会生效。", theme: .blue)
            }
        }
    }

    // MARK: - 内存分配

    private var memoryCard: some View {
        MyCard("内存分配", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    MyComboBox(checked: automaticModeBinding, text: MemoryAllocationMode.automatic.description, allowsUncheck: false)
                    MyComboBox(checked: customModeBinding, text: MemoryAllocationMode.custom.description, allowsUncheck: false)
                    Spacer()
                }

                HStack(spacing: 12) {
                    MySlider(
                        value: $memorySlider,
                        range: 0...Double(MemoryAllocation.maximumSliderPosition),
                        step: 1
                    )
                    .frame(height: 20)
                    .disabled(memoryMode == .automatic)
                    .opacity(memoryMode == .automatic ? 0.45 : 1)
                    .onChange(of: memorySlider) { newValue in
                        LauncherConfig.shared.memory = MemoryAllocation.megabytes(forSliderPosition: Int(newValue))
                    }
                    MyText(String(format: "%.1f GB", effectiveMemoryGB), size: 14)
                        .frame(width: 72, alignment: .trailing)
                }

                MemoryBar(
                    usedGigabytes: usedMemoryGB,
                    totalGigabytes: totalMemoryGB,
                    gameGigabytes: effectiveMemoryGB
                )

                MyText(
                    memoryMode == .automatic
                        ? "根据当前可用内存与版本类型自动决定分配量；想自己指定就切到「自定义」。"
                        : "拖动滑杆调整分配给游戏的内存。低内存区间刻度更细，便于微调。",
                    size: 12,
                    color: .colorGray3
                )
            }
        }
    }

    /// 当前生效的分配量（GB）。
    private var effectiveMemoryGB: Double {
        switch memoryMode {
        case .automatic:
            return automaticMemoryGB
        case .custom:
            return MemoryAllocation.gigabytes(forSliderPosition: Int(memorySlider))
        }
    }

    private var automaticModeBinding: Binding<Bool> {
        Binding(
            get: { memoryMode == .automatic },
            set: { isOn in
                guard isOn else { return }
                memoryMode = .automatic
                LauncherConfig.shared.memoryMode = .automatic
            }
        )
    }

    private var customModeBinding: Binding<Bool> {
        Binding(
            get: { memoryMode == .custom },
            set: { isOn in
                guard isOn else { return }
                memoryMode = .custom
                LauncherConfig.shared.memoryMode = .custom
                LauncherConfig.shared.memory = MemoryAllocation.megabytes(forSliderPosition: Int(memorySlider))
            }
        )
    }

    private func refreshMemoryReadings() {
        automaticMemoryGB = MemoryAllocation.recommendedGigabytes()
        usedMemoryGB = Double(MemoryAllocation.usedBytes) / 1_073_741_824
        totalMemoryGB = Double(MemoryAllocation.physicalBytes) / 1_073_741_824
    }

    // MARK: - 高级选项

    private var advancedCard: some View {
        MyCard("高级选项") {
            VStack(alignment: .leading, spacing: 12) {
                jvmArgumentsRow

                SettingRow("游戏参数", labelWidth: 140) {
                    MyTextField(text: $gameArguments, placeholder: "例如 --server example.com")
                        .onChange(of: gameArguments) { LauncherConfig.shared.gameArguments = $0 }
                }

                SettingRow("启动前执行命令", labelWidth: 140) {
                    MyTextField(text: $prelaunchCommand, placeholder: "例如 open -a CleanMyMac")
                        .onChange(of: prelaunchCommand) { LauncherConfig.shared.prelaunchCommand = $0 }
                }

                javaSection

                SettingRow("垃圾回收器", labelWidth: 140) {
                    MySelect($garbageCollector, entries: GarbageCollectorMode.menuOrder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: garbageCollector) { LauncherConfig.shared.garbageCollector = $0 }
                }
                MyText(garbageCollectorDescription, size: 12, color: .colorGray3)
                MyTip(
                    text: "选择具体策略后，会先移除清单与 JVM 参数里的 GC 相关项，再按策略补一套；选「不指定」则完全使用你写的参数。",
                    theme: .yellow
                )

                MyTip(text: "版本独立设置里还有更多高级选项可供调整。", theme: .blue)
                .padding(.top, 2)
            }
        }
    }

    /// JVM 参数行。
    ///
    /// PCL2 把「还原」做成标签右侧的小图标按钮（悬停才提示），而不是行尾一颗大按钮：
    /// 它属于这个输入框的附属操作，放在行尾会把输入框挤窄，也不符合原版的视觉层级。
    private var jvmArgumentsRow: some View {
        HStack(alignment: .top, spacing: 20) {
            HStack(spacing: 4) {
                MyText("Java 虚拟机参数")
                Image(.iconRefresh)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(resetHovered ? Color.color3 : .color1)
                    .padding(4)
                    .contentShape(.rect)
                    .onHover { resetHovered = $0 }
                    .onTapGesture(perform: restoreDefaultJVMArguments)
                    .help("还原默认")
            }
            .frame(width: 140, alignment: .leading)

            MyTextArea(text: $jvmArguments, placeholder: "例如 -XX:+AlwaysPreTouch -Dfile.encoding=UTF-8")
                .onChange(of: jvmArguments) { LauncherConfig.shared.jvmArguments = $0 }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func restoreDefaultJVMArguments() {
        jvmArguments = LauncherConfig.defaultJVMArguments
        LauncherConfig.shared.jvmArguments = LauncherConfig.defaultJVMArguments
        hint("已还原默认 JVM 参数", type: .finish)
    }

    private var garbageCollectorDescription: String {
        switch garbageCollector {
        case .autoZGC:
            return "Java 21+ 使用分代 ZGC，15–20 使用非分代 ZGC，14 及更早使用 G1GC。ZGC 在回收时不产生长时间停顿，代价是内存占用更高。"
        case .generationalZGC:
            return "Java 21+ 使用分代 ZGC，更早的版本回落到 G1GC。"
        case .g1:
            return "总是使用 G1GC，附带 Mojang 官方参数。"
        case .tunedG1:
            return "总是使用 G1GC，附带 PCL 调优过的参数：内存占用更低，但回收时可能出现短暂卡顿。"
        case .unspecified:
            return "不添加任何 GC 参数，完全交给上面的「Java 虚拟机参数」。"
        }
    }

    // MARK: - Java

    private var javaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MyText("Java 列表", size: 14)
                Spacer()
                MyButton("刷新") {
                    do {
                        try JavaManager.shared.research()
                        hint("刷新成功！", type: .finish)
                    } catch {
                        err("刷新 Java 列表失败：\(error.localizedDescription)")
                        hint("刷新 Java 列表失败：\(error.localizedDescription)", type: .critical)
                    }
                }
                .frame(width: 76)

                MyButton("安装") {
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
                .frame(width: 76)

                MyButton("手动添加") {
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
                .frame(width: 96)
            }

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

}
