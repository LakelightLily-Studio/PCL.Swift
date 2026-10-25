//
//  ToolboxPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/25.
//

import SwiftUI
import Core

struct ToolboxPage: View {
    @StateObject private var viewModel: ToolboxViewModel = .init()
    
    var body: some View {
        CardContainer {
            MyCard("百宝箱", foldable: false) {
                HStack {
                    MyButton("今日人品") {
                        let lucky: Int = viewModel.todayLucky
                        MessageBoxManager.shared.showText(
                            title: "今日人品 - \(viewModel.todayDate)",
                            content: "你今天的人品值是：\(viewModel.formatLucky(lucky))",
                            level: lucky <= 30 ? .error : .info
                        )
                    }
                    .frame(width: 120)
                    
                    MyButton("千万别点", type: .red) {
                        MessageBoxManager.shared.showText(
                            title: "警告",
                            content: "PCL.Swift 作者不会受理由于点击千万别点造成的任何 Bug。\n这是最后的警告，是否继续操作？",
                            level: .error,
                            .init(id: 0, label: "确定", type: .red),
                            .init(id: 1, label: "确定", type: .normal),
                            .init(id: 2, label: "确定", type: .normal)
                        ) { _ in
                            viewModel.executeEasterEgg()
                        }
                    }
                    .frame(width: 120)

                    MyButton("导出日志") {
                        do {
                            let url: URL = try SettingsViewModel.shared.exportLogs()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            err("导出日志失败：\(error.localizedDescription)")
                            hint("导出日志失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                    .frame(width: 120)
                    Spacer()
                }
                .frame(height: 40)
            }

            // 「实验功能」原先挂在 设置 → 其他 的调试卡里。那张卡按原版的
            // 「调试选项」删掉了，但这两个开关在本仓库没有第二个入口
            // （尤其「联机功能」：关掉之后顶栏的联机页签会整个消失），
            // 所以挪到百宝箱，避免功能被锁死。
            MyCard("实验功能", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    MyTip(text: "以下开关用于控制实验性功能及未经充分验证的更改。除非你了解其影响，否则请不要更改它们！", theme: .yellow)
                    MyComboBox(checked: binding(of: .deduplicateLibraries), text: "去除同一清单中的重复依赖库")
                    MyComboBox(checked: binding(of: .multiplayer), text: "联机功能")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardIndex(1)
        }
    }

    private func binding(of flag: FeatureFlag) -> Binding<Bool> {
        .init(
            get: { FlagsManager.shared.isEnabled(flag) },
            set: { FlagsManager.shared.setEnabled(flag, enabled: $0) }
        )
    }
}
