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
/// 现在个性化搬去了独立页（`PersonalizationSettingsPage`），其余两页合并成一页：
/// 它们描述的都是启动器自身的行为（怎么下载、导不导出日志、要不要检查更新）。
struct LauncherSettingsPage: View {
    @State private var downloadSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.downloadSourcePolicy
    
    var body: some View {
        CardContainer {
            MyCard("下载", foldable: false) {
                configLine(label: "下载源") {
                    MySelect(
                        $downloadSourcePolicy,
                        entries: [.officialFirst, .mirrorFirst]
                    )
                }
                .onChange(of: downloadSourcePolicy) { newValue in
                    DownloadSourceManager.shared.policy = newValue
                    LauncherConfig.shared.downloadSourcePolicy = newValue
                }
            }
            
            MyCard("调试", foldable: false) {
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
            .cardIndex(1)
            
            MyCard("启动器更新", foldable: false) {
                HStack {
                    MyButton("检查更新") {
                        UpdateService.shared.runInteractiveUpdateFlow(manually: true)
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 40)
            }
            .cardIndex(2)
        }
    }
    
    @ViewBuilder
    private func configLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, labelWidth: 80, content: body)
    }
    
    private func binding(of flag: FeatureFlag) -> Binding<Bool> {
        return .init(
            get: { FlagsManager.shared.isEnabled(flag) },
            set: { FlagsManager.shared.setEnabled(flag, enabled: $0) }
        )
    }
}
