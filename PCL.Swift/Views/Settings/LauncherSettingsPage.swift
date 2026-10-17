//
//  LauncherSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/9.
//

import SwiftUI
import Core

struct LauncherSettingsPage: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @State private var downloadSourcePolicy: DownloadSourcePolicy = LauncherConfig.shared.downloadSourcePolicy
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType
    @State private var theme: Theme = ThemeManager.shared.current
    
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
            
            MyCard("个性化", foldable: false) {
                configLine(label: "主页") {
                    MySelect(
                        $homepageType,
                        entries: [.empty, .demo]
                    )
                }
                .onChange(of: homepageType) { newValue in
                    LauncherConfig.shared.homepageType = newValue
                }
                
                configLine(label: "主题色") {
                    MySelect(
                        $theme,
                        entries: Theme.allCases
                    )
                }
                .onChange(of: theme) { newValue in
                    themeManager.set(newValue)
                }
            }
            .cardIndex(1)
        }
    }
    
    @ViewBuilder
    private func configLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, labelWidth: 80, content: body)
    }
}
