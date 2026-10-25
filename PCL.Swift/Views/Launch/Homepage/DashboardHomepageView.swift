//
//  DashboardHomepageView.swift
//  PCL.Swift
//
//  启动页右侧的启动器主页：账号与皮肤、更新公告、Minecraft 新闻。
//
//  这里的数据都是"打开就有"的类型：新闻与更新检查失败时只显示一行说明 + 重试，
//  不弹窗——主页不该在启动器刚打开时打断用户。
//

import SwiftUI
import AppKit
import Core

struct DashboardHomepageView: View {
    @StateObject private var accountVM: AccountViewModel = .init()
    @State private var news: [MinecraftNewsItem] = []
    @State private var newsFailed: Bool = false
    @State private var loadingNews: Bool = false
    @State private var latestVersion: UpdateModel.Version?

    var body: some View {
        CardContainer {
            HStack(alignment: .top, spacing: 15) {
                accountCard
                    .frame(maxWidth: .infinity)
                updateCard
                    .frame(maxWidth: .infinity)
            }
            newsCard
                .cardIndex(1)
        }
        .task { await reloadNews() }
        .task { await checkUpdate() }
    }

    // MARK: - 账号与皮肤

    private var accountCard: some View {
        MyCard("账号与皮肤", foldable: false) {
            HStack(spacing: 16) {
                if let account = accountVM.currentAccount {
                    PlayerAvatar(account, length: 96)
                    VStack(alignment: .leading, spacing: 5) {
                        MyText(account.profile.name, size: 16)
                            .lineLimit(1)
                        MyText(typeName(account.type), size: 12, color: .colorGray3)
                        MyText("皮肤来自当前账号", size: 12, color: .colorGray3)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        MyText("还没有登录账号", size: 15)
                        MyText("在左侧面板登录后，这里会显示你的皮肤。", size: 12, color: .colorGray3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 100)
        }
    }

    private func typeName(_ type: AccountType) -> String {
        switch type {
        case .offline: "离线账户"
        case .microsoft: "微软账户"
        case .yggdrasil: "第三方账户"
        }
    }

    // MARK: - 更新公告

    private var updateCard: some View {
        MyCard("更新公告", foldable: false) {
            VStack(alignment: .leading, spacing: 8) {
                MyText("当前版本 " + Metadata.appVersion, size: 12, color: .colorGray3)

                if let latestVersion {
                    MyText(latestVersion.name, size: 15)
                    MyText(latestVersion.summary, size: 12, color: .colorGray2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        MyButton("下载并安装", type: .highlight) {
                            UpdateService.shared.runInteractiveUpdateFlow(manually: true)
                        }
                        .frame(width: 120)
                        Spacer()
                    }
                } else {
                    MyText("已是最新版本", size: 13)
                    MyText("启动器发现新版本时会在这里显示。", size: 12, color: .colorGray3)
                    HStack {
                        MyButton("检查更新") {
                            UpdateService.shared.runInteractiveUpdateFlow(manually: true)
                        }
                        .frame(width: 110)
                        Spacer()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 100, alignment: .top)
        }
    }

    // MARK: - 新闻

    private var newsCard: some View {
        MyCard("Minecraft 新闻", foldable: false) {
            VStack(alignment: .leading, spacing: 8) {
                if news.isEmpty {
                    HStack(spacing: 10) {
                        MyText(
                            newsFailed ? "新闻加载失败，请检查网络连接。" : "正在加载新闻…",
                            size: 12,
                            color: .colorGray3
                        )
                        Spacer(minLength: 0)
                        if newsFailed {
                            MyButton("重试") {
                                Task { await reloadNews() }
                            }
                            .frame(width: 80)
                        }
                    }
                    .frame(height: 40)
                } else {
                    ForEach(news) { item in
                        newsRow(item)
                    }
                }
            }
        }
    }

    private func newsRow(_ item: MinecraftNewsItem) -> some View {
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

    // MARK: - 数据

    private func reloadNews() async {
        loadingNews = true
        defer { loadingNews = false }
        do {
            news = try await MinecraftNewsService.fetch(limit: 3)
            newsFailed = false
        } catch let error where error.isCancellationError {
        } catch {
            newsFailed = true
            warn("加载 Minecraft 新闻失败：\(error.localizedDescription)")
        }
    }

    private func checkUpdate() async {
        guard !LauncherConfig.shared.ignoreLauncherUpdates else { return }
        do {
            latestVersion = try await UpdateManager.shared.checkUpdates()
        } catch {
            warn("检查启动器更新失败：\(error.localizedDescription)")
        }
    }
}
