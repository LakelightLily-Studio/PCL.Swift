//
//  LaunchPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI
import Core

struct LaunchPage: View {
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared

    var body: some View {
        switch LauncherConfig.shared.homepageType {
        case .empty:
            // 空白主页：右侧不渲染任何内容。原来那套「启动器主页」
            // （账号皮肤 / 更新公告 / Minecraft 新闻）已按需求整页删除。
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .preset:
            presetView
        case .local:
            CustomHomepageView(source: .localFile)
        case .remote:
            remoteView
        case .demo:
            DemoHomepageView()
        }
    }

    @ViewBuilder
    private var presetView: some View {
        switch LauncherConfig.shared.homepagePreset {
        case .changelog:
            // 原生视图，不走自定义主页的解析：内容与渲染都在我们手里，也不需要那层测试期提示。
            ChangelogHomepageView()
        case .minecraftNews:
            // 与原版一致：下载作者的 XAML 再解析；那台服务器不稳或地区不可达时，
            // 退回内置的官方新闻源渲染，保证这一项永远有内容。
            CustomHomepageView(
                source: .remote(HomepageLoader.minecraftNewsPresetURL),
                fallback: AnyView(NewsHomepageView())
            )
        }
    }

    @ViewBuilder
    private var remoteView: some View {
        if let url = URL(string: LauncherConfig.shared.homepageURL),
           let scheme = url.scheme,
           scheme.hasPrefix("http") {
            CustomHomepageView(source: .remote(url))
        } else {
            VStack(spacing: 10) {
                MyTip(text: "还没有填写主页下载地址。请到 设置 → 个性化 → 主页 里填写 Custom.xaml 的网址。", theme: .yellow)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
