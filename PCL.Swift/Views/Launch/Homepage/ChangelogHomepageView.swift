//
//  ChangelogHomepageView.swift
//  PCL.Swift
//
//  主页预设「PCL.Swift 更新日志」。
//
//  每个版本一张卡片、默认展开：主页打开就能看到这一版改了什么，不用去翻 Release 页。
//  内容来自国内分发仓库（见 ChangelogLoader），失败时退回缓存与打包进 App 的那份。
//

import SwiftUI
import Core

struct ChangelogHomepageView: View {
    @State private var document: ChangelogDocument?
    @State private var source: Source = .none
    @State private var errorMessage: String?
    @State private var refreshing: Bool = false

    /// 当前内容的来源，显示在卡片上方。
    private enum Source {
        case none, bundled, cache, remote

        var description: String {
            switch self {
            case .none: ""
            case .bundled: "更新日志来自 App 内置副本"
            case .cache: "更新日志来自上次的缓存"
            case .remote: "更新日志来自国内分发仓库"
            }
        }
    }

    var body: some View {
        CardContainer {
            header

            if let document {
                ForEach(Array(document.entries.enumerated()), id: \.element.id) { index, entry in
                    card(entry)
                        .cardIndex(index)
                }
            } else if let errorMessage {
                MyTip(text: errorMessage, theme: .red)
            } else {
                MyText("正在加载更新日志…", color: .colorGray3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await load() }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 10) {
            MyText(source.description, size: 12, color: .colorGray3)
                .lineLimit(1)
            Spacer(minLength: 0)
            MyButton("刷新", disabled: refreshing) {
                Task { await refresh() }
            }
            .frame(width: 90)
        }
    }

    // MARK: - 卡片

    private func card(_ entry: ChangelogEntry) -> some View {
        // folded: false —— 更新日志默认展开，这是这个预设唯一存在的意义。
        MyCard(title(entry), foldable: true, folded: false) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func title(_ entry: ChangelogEntry) -> String {
        entry.version == Metadata.appVersion ? entry.version + "（当前版本）" : entry.version
    }

    private func sectionView(_ section: ChangelogSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !section.title.isEmpty {
                MyText(section.title, size: 12, color: .colorGray3)
            }
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    MyText("·", size: 13, color: .colorGray3)
                    itemText(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemText(_ item: ChangelogItem) -> some View {
        var text: Text = Text("")
        for run in item.runs {
            var piece: Text = Text(run.text)
            if run.bold { piece = piece.bold() }
            if run.code { piece = piece.foregroundColor(.color2) }
            text = text + piece
        }
        return text
            .font(.custom("PCLEnglish", size: 13))
            .foregroundStyle(Color.color1)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 加载

    private func load() async {
        // 先用手里已有的内容铺满页面，再去联网：断网时也不会先闪一下"加载失败"。
        if let cached = ChangelogLoader.loadCached() {
            document = cached
            source = .cache
        } else if let bundled = ChangelogLoader.loadBundled() {
            document = bundled
            source = .bundled
        }
        await refresh()
    }

    private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            document = try await ChangelogLoader.loadRemote()
            source = .remote
            errorMessage = nil
        } catch let error where error.isCancellationError {
        } catch {
            warn("加载更新日志失败：\(error.localizedDescription)")
            if document == nil {
                errorMessage = "更新日志加载失败：" + error.localizedDescription
            }
        }
    }
}
