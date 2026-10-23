//
//  InstanceExportPage.swift
//  PCL.Swift
//
//  实例导出：整合包（.mrpack）与启动脚本。
//

import SwiftUI
import Core

struct InstanceExportPage: View {
    @StateObject private var viewModel: InstanceExportViewModel

    init(instanceManager: InstanceManager, id: String) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id))
    }

    var body: some View {
        CardContainer {
            MyCard("导出整合包", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingRow("整合包名称", labelWidth: 90) {
                        MyTextField(text: $viewModel.packName, placeholder: "整合包名称")
                    }
                    SettingRow("整合包版本", labelWidth: 90) {
                        MyTextField(text: $viewModel.packVersion, placeholder: "例如 1.0.0")
                    }
                    MyComboBox(checked: $viewModel.includeUnrecognizedFiles, text: "把无法识别的文件一并打包进整合包")
                    MyComboBox(checked: $viewModel.includeLauncherConfig, text: "包含启动器配置")
                    MyTip(text: "只有 Modrinth 上能按哈希识别的文件会写成下载条目，其余文件按上面的选项决定是否直接打包。存档、日志与截图不会被导出。", theme: .blue)
                    HStack {
                        MyButton("开始导出", type: .highlight) {
                            viewModel.exportModpack()
                        }
                        .frame(width: 130)
                        Spacer()
                    }
                    .frame(height: 35)
                }
            }

            MyCard("导出启动脚本", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    MyText("把当前实例的 JVM 与游戏参数展开成一个可执行的 shell 脚本。", size: 12, color: .colorGray2)
                    MyTip(text: "脚本里的 accessToken 会被替换为占位符，直接运行会以离线身份进入游戏。", theme: .yellow)
                    HStack {
                        MyButton("导出脚本") {
                            viewModel.exportScript()
                        }
                        .frame(width: 130)
                        Spacer()
                    }
                    .frame(height: 35)
                }
            }
            .cardIndex(1)
        }
    }
}
