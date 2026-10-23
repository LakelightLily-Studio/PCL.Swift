//
//  InstanceConfigPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI
import Core

struct InstanceConfigPage: View {
    @StateObject private var viewModel: InstanceConfigViewModel

    init(instanceManager: InstanceManager, id: String) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id))
    }

    var body: some View {
        CardContainer {
            MyCard(nil, padding: 10) {
                MyListItem { _ in
                    HStack(spacing: 0) {
                        InstanceIconView(icon: viewModel.icon)
                            .frame(width: 36, height: 36)
                            .padding(.trailing, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            MyText(viewModel.instance.title)
                                .lineLimit(1)
                            MyText(viewModel.description, color: .colorGray3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            MyCard(nil) {
                HStack {
                    MyButton("打开实例目录") {
                        NSWorkspace.shared.open(viewModel.instance.url)
                    }
                    .frame(width: 120)
                    MyButton("删除实例", type: .red) {
                        MessageBoxManager.shared.showText(
                            title: "确认",
                            content: "你确定要删除这个实例（\(viewModel.instance.title)）吗？\n这个实例的所有存档、模组、资源包等将会永久消失！（真的很久！）",
                            level: .error,
                            .no(),
                            .yes(type: .red)
                        ) { result in
                            if result == 1 {
                                do {
                                    try viewModel.deleteInstance()
                                    hint("删除成功！", type: .finish)
                                    AppRouter.shared.removeLast()
                                } catch {
                                    hint("删除实例失败：\(error.localizedDescription)", type: .critical)
                                }
                            }
                        }
                    }
                    .frame(width: 120)
                    Spacer()
                }
                .frame(height: 35)
            }
            .cardIndex(1)
            jvmCard.cardIndex(2)
            windowCard.cardIndex(3)
            processCard.cardIndex(4)
            advancedCard.cardIndex(5)
        }
    }

    // MARK: - JVM

    @ViewBuilder
    private var jvmCard: some View {
        MyCard("JVM 设置", foldable: false) {
            configLine(label: "使用的 Java") {
                MyText(viewModel.javaDescription)
            }
            configLine(label: "内存分配") {
                MyTextField(text: $viewModel.jvmHeapSize)
                    .onChange(of: viewModel.jvmHeapSize) { newValue in
                        if let jvmHeapSize: UInt64 = .init(newValue) { viewModel.setHeapSize(jvmHeapSize) }
                    }
                MyText("MB")
            }
            configLine(label: "额外 JVM 参数") {
                MyTextField(text: $viewModel.jvmArguments, placeholder: "例如 -XX:+UseG1GC -Dfile.encoding=UTF-8，将被追加至原本 JVM 参数后")
                    .onChange(of: viewModel.jvmArguments) { newValue in
                        viewModel.setJvmArguments(newValue)
                    }
            }
            HStack(spacing: 30) {
                MyButton("切换 Java") {
                    let runtimes: [JavaRuntime] = viewModel.javaList()
                    MessageBoxManager.shared.showList(
                        title: "切换 Java",
                        items: runtimes.map { .init(name: $0.description, description: $0.executableURL.path) }
                    ) { index in
                        guard let index else { return }
                        let runtime: JavaRuntime = runtimes[index]
                        do {
                            try viewModel.switchJava(to: runtime)
                        } catch let error as InstanceConfigViewModel.Error {
                            switch error {
                            case .invalidJavaVersion(let min):
                                MessageBoxManager.shared.showText(
                                    title: "Java 版本不满足要求",
                                    content: "这个实例需要 Java \(min) 才能启动，但你选择的是 Java \(runtime.version)！",
                                    level: .error
                                )
                            }
                        } catch {
                            err("切换 Java 失败：\(error.localizedDescription)")
                            hint("切换 Java 失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                }
                .frame(minWidth: 150)
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }
            .frame(height: 35)
            .padding(.top, 12)
        }
    }

    // MARK: - 窗口

    @ViewBuilder
    private var windowCard: some View {
        MyCard("游戏窗口", foldable: false) {
            configLine(label: "窗口标题") {
                MyTextField(text: $viewModel.windowTitle, placeholder: "留空则使用游戏自身标题")
                    .disabled(viewModel.followsGlobalWindowTitle)
                followToggle($viewModel.followsGlobalWindowTitle)
            }

            if !GameWindowTitle.isTrusted {
                MyTip(text: "修改游戏窗口标题需要「辅助功能」权限，可以在「设置 → 游戏」里授权。", theme: .yellow)
            }
            configLine(label: "窗口模式") {
                MySelect($viewModel.windowType, entries: GameWindowType.allCases)
            }
            if viewModel.windowType == .custom {
                configLine(label: "窗口大小") {
                    MyTextField(text: $viewModel.windowWidth)
                        .frame(width: 80)
                        .disabled(viewModel.followsGlobalWindowSize)
                    MyText("×")
                    MyTextField(text: $viewModel.windowHeight)
                        .frame(width: 80)
                        .disabled(viewModel.followsGlobalWindowSize)
                    followToggle($viewModel.followsGlobalWindowSize)
                }
            }
            saveRow
        }
    }

    // MARK: - 进程

    @ViewBuilder
    private var processCard: some View {
        MyCard("启动行为", foldable: false) {
            configLine(label: "启动器可见性") {
                MySelect($viewModel.launcherVisibility, entries: LauncherVisibility.allCases)
                    .frame(width: 200)
                    .disabled(viewModel.followsGlobalVisibility)
                followToggle($viewModel.followsGlobalVisibility)
            }
            configLine(label: "进程优先级") {
                MySelect($viewModel.processPriority, entries: ProcessPriority.allCases)
                    .frame(width: 120)
                    .disabled(viewModel.followsGlobalPriority)
                followToggle($viewModel.followsGlobalPriority)
            }
            configLine(label: "启动前执行命令") {
                MyTextField(text: $viewModel.prelaunchCommand, placeholder: "例如 rm -rf caches/ 或 open -a CleanMyMac")
                    .disabled(viewModel.followsGlobalPrelaunch)
                followToggle($viewModel.followsGlobalPrelaunch)
            }
            configLine(label: "等待命令完成") {
                MyComboBox(checked: $viewModel.prelaunchWaitForCompletion, text: "命令执行完成后才继续启动")
                Spacer(minLength: 0)
            }
            configLine(label: "内存优化") {
                MyComboBox(checked: $viewModel.memoryOptimize, text: "启动游戏前进行内存优化")
                    .disabled(viewModel.followsGlobalMemoryOptimize)
                followToggle($viewModel.followsGlobalMemoryOptimize)
            }
            saveRow
        }
    }

    // MARK: - 高级

    @ViewBuilder
    private var advancedCard: some View {
        MyCard("游戏参数", foldable: false) {
            configLine(label: "附加游戏参数") {
                MyTextField(text: $viewModel.gameArguments, placeholder: "例如 --server example.com --port 25565")
                    .disabled(viewModel.followsGlobalGameArguments)
                followToggle($viewModel.followsGlobalGameArguments)
            }
            MyTip(text: "窗口相关的 --width / --height / --fullscreen 会被上面的「游戏窗口」设置接管，在这里重复填写不会生效。", theme: .blue)
            saveRow
        }
    }

    // MARK: - 组件

    /// 「跟随全局」开关。勾上时输入框禁用，值取全局设置。
    private func followToggle(_ binding: Binding<Bool>) -> some View {
        MyComboBox(checked: binding, text: "跟随全局")
    }

    private var saveRow: some View {
        HStack {
            Spacer()
            MyButton("保存设置", type: .highlight) {
                viewModel.save()
                hint("实例设置已保存！", type: .finish)
            }
            .frame(width: 120)
        }
        .frame(height: 35)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func configLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, content: body)
    }
}
