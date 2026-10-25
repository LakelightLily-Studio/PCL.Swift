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
        case .dashboard:
            DashboardHomepageView()
        case .preset:
            customHomepage(presetView)
        case .local:
            customHomepage(CustomHomepageView(source: .localFile))
        case .remote:
            customHomepage(remoteView)
        case .demo:
            DemoHomepageView()
        }
    }

    /// 自定义主页（预设 / 本地 / 联网）统一套一层测试期提示：
    /// 这套解析与渲染还比较重，复杂主页在低配机器上会明显掉帧。
    private func customHomepage<Content: View>(_ content: Content) -> some View {
        VStack(spacing: 0) {
            MyTip(text: "主页自定义仍处于测试阶段，渲染开销较大、性能可能不佳，请酌情使用。", theme: .yellow)
                .padding(.horizontal, 25)
                .padding(.top, 25)
            content
        }
    }

    @ViewBuilder
    private var presetView: some View {
        switch LauncherConfig.shared.homepagePreset {
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
