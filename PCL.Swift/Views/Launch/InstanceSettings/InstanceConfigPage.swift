//
//  InstanceConfigPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI
import Core

/// 实例设置 → 设置。
///
/// 卡片与行序对齐 PCL2 的 PageInstanceSetup：顶部提示、启动选项、内存分配、服务器、高级选项。
///
/// - 「版本隔离」是真的：关闭后存档 / Mod / options.txt 落到仓库根目录，与关闭隔离的版本共用；
/// - 「游戏窗口标题 / 自定义信息」需要 PCL 的 Java Wrapper 注入，macOS 没有对应通道，
///   现在只保存、不生效（见卡片末尾说明）；
/// - 「服务器」卡还没有按实例配置登录的能力，保留原版位置做占位。
struct InstanceConfigPage: View {
    @StateObject private var viewModel: InstanceConfigViewModel

    /// 内存条读数：进页面时取一次，避免每次布局都做 syscall。
    @State private var usedMemoryGB: Double = 0
    @State private var totalMemoryGB: Double = 1

    init(instanceManager: InstanceManager, id: String) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id))
    }

    var body: some View {
        CardContainer {
            MyTip(text: "这些设置只对该游戏版本生效，不影响其他版本。", theme: .blue)
            launchOptionsCard
            memoryCard
                .cardIndex(1)
            serverCard
                .cardIndex(2)
            advancedCard
                .cardIndex(3)
        }
        .onAppear(perform: refreshMemoryReadings)
    }

    // MARK: - 启动选项

    private var launchOptionsCard: some View {
        MyCard("启动选项", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("版本隔离", labelWidth: 120) {
                    MySelect(Binding(
                        get: { viewModel.isolation ? "开启" : "关闭" },
                        set: { viewModel.isolation = $0 == "开启" }
                    ), entries: ["开启", "关闭"])
                    .frame(maxWidth: .infinity)
                    .help("关闭后，存档、Mod 与 options.txt 会写到仓库根目录，与同样关闭隔离的版本共用。")
                }

                SettingRow("Java", labelWidth: 120) {
                    MySelect(javaBinding, entries: javaEntries)
                        .frame(maxWidth: .infinity)
                }

                if needsJava {
                    MyTip(text: "你的电脑上没有可供该版本使用的 Java，启动时会提示安装。", theme: .yellow)
                }
            }
        }
    }

    private var javaEntries: [String] {
        ["自动选择"] + viewModel.javaChoices().map(\.description)
    }

    private var javaBinding: Binding<String> {
        .init(
            get: { viewModel.instance.config.javaURL == nil ? "自动选择" : viewModel.javaDescription },
            set: { value in
                if value == "自动选择" {
                    viewModel.setAutomaticJava()
                    return
                }
                guard let runtime = viewModel.javaChoices().first(where: { $0.description == value }) else { return }
                do {
                    try viewModel.switchJava(to: runtime)
                } catch let error as InstanceConfigViewModel.Error {
                    switch error {
                    case .invalidJavaVersion(let min):
                        MessageBoxManager.shared.showText(
                            title: "Java 版本不满足要求",
                            content: "这个实例需要 Java \(min) 才能启动，但你选择的是 \(runtime.version)！",
                            level: .error
                        )
                    }
                } catch {
                    err("切换 Java 失败：\(error.localizedDescription)")
                    hint("切换 Java 失败：\(error.localizedDescription)", type: .critical)
                }
            }
        )
    }

    private var needsJava: Bool {
        JavaSearcher.pick(for: viewModel.instance) == nil
    }

    // MARK: - 内存分配

    private var memoryCard: some View {
        MyCard("内存分配", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                // 内存分配是单选：与原版一样用圆形单选框，不用方形复选框。
                HStack(spacing: 20) {
                    MyRadioBox(checked: memoryModeBinding(nil), text: "跟随全局设置")
                    MyRadioBox(checked: memoryModeBinding(.automatic), text: "自动配置")
                    MyRadioBox(checked: memoryModeBinding(.custom), text: "自定义")
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    MySlider(value: customMemoryBinding, range: 0...Double(MemoryAllocation.maximumSliderPosition), step: 1)
                        .disabled(viewModel.memoryMode != .custom)
                        .opacity(viewModel.memoryMode == .custom ? 1 : 0.45)
                    MyText(String(format: "%.1f GB", effectiveMemoryGB), size: 12, color: .colorGray3)
                        .frame(width: 64, alignment: .trailing)
                }

                SettingRow("启动游戏前进行内存优化", labelWidth: 160) {
                    MySelect(.constant("跟随全局设置"), entries: ["跟随全局设置"])
                        .frame(maxWidth: .infinity)
                        .disabled(true)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }

                MemoryBar(
                    usedGigabytes: usedMemoryGB,
                    totalGigabytes: totalMemoryGB,
                    gameGigabytes: effectiveMemoryGB
                )
            }
        }
    }

    private var effectiveMemoryGB: Double {
        switch viewModel.memoryMode {
        case .automatic:
            return MemoryAllocation.recommendedGigabytes(
                modCount: viewModel.modCount,
                modable: viewModel.instance.modLoader != nil
            )
        case .custom:
            return Double(UInt64(viewModel.jvmHeapSize) ?? 0) / 1024
        case .none:
            return Double(LauncherConfig.shared.resolvedMemoryMB()) / 1024
        }
    }

    private var customMemoryBinding: Binding<Double> {
        .init(
            get: {
                Double(MemoryAllocation.sliderPosition(
                    forGigabytes: Double(UInt64(viewModel.jvmHeapSize) ?? 0) / 1024
                ))
            },
            set: { position in
                viewModel.setHeapSize(MemoryAllocation.megabytes(forSliderPosition: Int(position)))
            }
        )
    }

    private func memoryModeBinding(_ mode: MemoryAllocationMode?) -> Binding<Bool> {
        .init(
            get: { viewModel.memoryMode == mode },
            set: { checked in
                guard checked else { return }
                viewModel.memoryMode = mode
            }
        )
    }

    private func refreshMemoryReadings() {
        usedMemoryGB = Double(MemoryAllocation.usedBytes) / 1_073_741_824
        totalMemoryGB = Double(MemoryAllocation.physicalBytes) / 1_073_741_824
    }

    // MARK: - 服务器（占位）

    private var serverCard: some View {
        MyCard("服务器", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("登录方式", labelWidth: 120) {
                    MySelect(.constant("正版登录或离线登录"), entries: ["正版登录或离线登录"])
                        .frame(maxWidth: .infinity)
                        .disabled(true)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }
                SettingRow("自动进入服务器", labelWidth: 120) {
                    MyTextField(text: .constant(""), placeholder: "例如 example.com:25565")
                        .disabled(true)
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }
                MyTip(text: "占位：按版本配置第三方登录与自动进服还没实现，登录方式目前跟随账号；自动进服可以先用「高级选项 → 游戏参数」里的 --server。", theme: .yellow)
            }
        }
    }

    // MARK: - 高级选项

    private var advancedCard: some View {
        MyCard("高级选项") {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("Java 虚拟机参数", labelWidth: 140) {
                    MyTextField(text: $viewModel.jvmArguments, placeholder: "留空则跟随全局设置")
                        .onChange(of: viewModel.jvmArguments) { newValue in
                            viewModel.setJvmArguments(newValue)
                        }
                }

                SettingRow("游戏参数", labelWidth: 140) {
                    MyTextField(text: $viewModel.gameArguments, placeholder: "留空则跟随全局设置")
                }

                SettingRow("内存管理", labelWidth: 140) {
                    MySelect(garbageCollectorBinding, entries: garbageCollectorEntries)
                        .frame(maxWidth: .infinity)
                }

                SettingRow("启动前执行命令", labelWidth: 140) {
                    MyTextField(text: $viewModel.prelaunchCommand, placeholder: "留空则跟随全局设置")
                }

                MyTip(text: "全局设置中还有更多选项可供调整。", theme: .blue)
            }
        }
    }

    /// 垃圾回收器的实例覆盖：第一项是「跟随全局设置」，其余与设置页一致。
    private var garbageCollectorEntries: [String] {
        ["跟随全局设置"] + GarbageCollectorMode.menuOrder.map(\.description)
    }

    private var garbageCollectorBinding: Binding<String> {
        .init(
            get: { viewModel.garbageCollector?.description ?? "跟随全局设置" },
            set: { value in
                viewModel.garbageCollector = GarbageCollectorMode.menuOrder.first { $0.description == value }
            }
        )
    }
}
