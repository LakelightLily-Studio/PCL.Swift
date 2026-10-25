//
//  NewsHomepageView.swift
//  PCL.Swift
//
//  主页预设「Minecraft 新闻」。
//
//  原版这个预设是下载一份 XAML（作者的新闻主页）再交给 XAML 解析器；
//  那台服务器不稳定，这里直接接官方启动器的新闻内容源，
//  效果相同还不依赖第三方服务器。
//

import SwiftUI
import AppKit
import Core

struct NewsHomepageView: View {
    @State private var news: [MinecraftNewsItem] = []
    @State private var failed: Bool = false
    @State private var loading: Bool = false

    var body: some View {
        CardContainer {
            MyCard("Minecraft 新闻", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        MyText("内容来自 Minecraft 官方启动器的新闻源", size: 12, color: .colorGray3)
                        Spacer(minLength: 0)
                        MyButton("刷新") {
                            Task { await load() }
                        }
                        .frame(width: 90)
                    }

                    if news.isEmpty {
                        MyText(failed ? "新闻加载失败，请检查网络连接。" : "正在加载新闻…", size: 12, color: .colorGray3)
                            .frame(height: 40)
                    } else {
                        ForEach(news) { item in
                            row(item)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func row(_ item: MinecraftNewsItem) -> some View {
        MyListItem { _ in
            HStack(spacing: 12) {
                if let imageURL = item.imageURL {
                    NetworkImage(url: imageURL)
                        .frame(width: 120, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    MyText(item.title)
                        .lineLimit(2)
                    MyText("\(item.category) · \(item.date)", size: 11, color: .colorGray3)
                }
                Spacer(minLength: 0)
            }
        }
        .pointingHandCursor(isEnabled: item.link != nil)
        .onTapGesture {
            guard let link = item.link else { return }
            NSWorkspace.shared.open(link)
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            news = try await MinecraftNewsService.fetch(limit: 5)
            failed = false
        } catch let error where error.isCancellationError {
        } catch {
            failed = true
            warn("加载 Minecraft 新闻失败：\(error.localizedDescription)")
        }
    }
}
