//
//  CustomHomepageView.swift
//  PCL.Swift
//
//  渲染 HomepageDocument（本地文件 / 联网更新的原版主页）。
//
//  解析在 Core，这里负责把节点映射到现有控件，并承担原版主页的运行期语义：
//  页面变量（{variable}）、条件可见性、按钮事件（网页 / 弹窗 / 启动游戏 / 切页）。
//

import SwiftUI
import AppKit
import Core

enum HomepageSource: Equatable {
    case localFile
    case remote(URL)
}

struct CustomHomepageView: View {
    let source: HomepageSource
    /// 加载失败时的替代内容（预设用它退回内置新闻页）。
    var fallback: AnyView?

    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var document: HomepageDocument?
    @State private var errorMessage: String?
    @State private var loading: Bool = false

    var body: some View {
        Group {
            if let document {
                HomepageDocumentView(document: document) {
                    Task { await reload() }
                }
            } else if let fallback, errorMessage != nil {
                fallback
            } else if let errorMessage {
                VStack(spacing: 10) {
                    MyTip(text: errorMessage, theme: .red)
                    HStack {
                        MyButton("重试") { Task { await reload() } }
                            .frame(width: 100)
                        Spacer()
                    }
                }
                .padding(25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                MyText("正在加载主页…", color: .colorGray3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await reload() }
        .onChange(of: configObserver.tick) { _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            switch source {
            case .localFile:
                document = try HomepageLoader.loadLocalFile()
            case .remote(let url):
                document = try await HomepageLoader.loadRemote(url)
            }
            errorMessage = nil
        } catch {
            document = nil
            errorMessage = "主页加载失败：" + error.localizedDescription
            warn("加载自定义主页失败：\(error.localizedDescription)")
        }
    }
}

/// 文档树渲染。
struct HomepageDocumentView: View {
    let document: HomepageDocument
    let onRefresh: () -> Void

    /// 页面变量。原版用 {variable:Name:Default} 读、用「修改变量」事件写。
    @State private var variables: [String: String] = [:]

    private static let hints: [String] = [
        "你知道吗？PCL.Swift 的界面动画参数大多直接取自 PCL2。",
        "你知道吗？在 设置 → 启动 里可以把垃圾回收器换成 ZGC。",
        "你知道吗？实例设置里的「版本隔离」关闭后，存档会与同目录下的版本共用。",
        "你知道吗？按住 Option 再点击卡片标题，可以一次性折叠整页卡片。"
    ]

    var body: some View {
        CardContainer {
            ForEach(Array(topLevelNodes.enumerated()), id: \.offset) { index, node in
                render(node)
                    .cardIndex(index)
            }
        }
    }

    /// 原版主页通常被包在一层纵向 StackPanel 里；展开这一层，卡片才能按容器间距排列。
    private var topLevelNodes: [HomepageNode] {
        if document.nodes.count == 1,
           case .stack(.vertical, _, let children) = document.nodes[0] {
            return children
        }
        return document.nodes
    }

    // MARK: - 渲染

    private func render(_ node: HomepageNode) -> AnyView {
        switch node {
        case .stack(let axis, let alignment, let children):
            let items = ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
            if axis == .horizontal {
                return AnyView(
                    HStack(spacing: 8) { items }
                        .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
                )
            }
            return AnyView(
                VStack(alignment: alignment.horizontalAlignment, spacing: 8) { items }
                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            )

        case .card(let title, let foldable, let folded, let children):
            let items = ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
            return AnyView(
                MyCard(title, foldable: foldable, folded: folded) {
                    VStack(alignment: .leading, spacing: 8) { items }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            )

        case .richText(let runs, let alignment):
            let text: AttributedString = attributed(runs)
            // 整段都是透明阴影副本时不要占位。
            guard !text.characters.isEmpty else { return AnyView(EmptyView()) }
            return AnyView(
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            )

        case .hint(let text, let theme):
            return AnyView(MyTip(text: resolve(text), theme: theme.myTipTheme))

        case .button(let label, let style, let events):
            return AnyView(
                HStack {
                    MyButton(resolve(label), type: style.myButtonType) { perform(events) }
                        .frame(minWidth: 120)
                    Spacer(minLength: 0)
                }
            )

        case .textButton(let label, let alignment, let events):
            return AnyView(
                MyText(resolve(label), color: events.isEmpty ? .color1 : .color2)
                    .contentShape(.rect)
                    .onTapGesture { perform(events) }
                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            )

        case .image(let source, let height, let width, let alignment):
            return AnyView(
                imageView(source: source, height: height, width: width)
                    .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
            )

        case .grid(let columns, let cells):
            return AnyView(gridView(columns: columns, cells: cells))

        case .wrap(let children):
            let items = ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                render(child)
            }
            return AnyView(
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) { items }
                .frame(maxWidth: .infinity, alignment: .leading)
            )

        case .conditional(let name, let defaultValue, let child):
            let value: String = variables[name] ?? defaultValue
            return value.lowercased() == "collapsed" ? AnyView(EmptyView()) : render(child)
        }
    }

    // MARK: - Grid

    private func gridView(columns: [HomepageGridLength], cells: [HomepageGridCell]) -> some View {
        let rowCount: Int = max(cells.map { $0.row + max($0.rowSpan, 1) }.max() ?? 1, 1)
        return VStack(spacing: 8) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { column, length in
                        let stack: [HomepageGridCell] = cells.filter { $0.row == row && $0.column == column }
                        if stack.isEmpty {
                            if !isCovered(row: row, column: column, cells: cells) {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 1)
                            }
                        } else {
                            // 同一个格子里可能有多个元素（原版用 Grid 叠放做阴影），按 ZStack 叠加。
                            ZStack(alignment: .topLeading) {
                                ForEach(Array(stack.enumerated()), id: \.offset) { _, cell in
                                    sized(render(cell.node), length)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 该格是否被左侧跨列的单元格占住。
    private func isCovered(row: Int, column: Int, cells: [HomepageGridCell]) -> Bool {
        cells.contains { cell in
            cell.row == row && column > cell.column && column < cell.column + max(cell.columnSpan, 1)
        }
    }

    @ViewBuilder
    private func sized(_ content: AnyView, _ length: HomepageGridLength) -> some View {
        switch length {
        case .fixed(let width):
            content.frame(width: width, alignment: .leading)
        case .flexible:
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 富文本

    private func attributed(_ runs: [HomepageTextRun]) -> AttributedString {
        var result: AttributedString = .init()
        for run in runs {
            if let color = run.color, color.count == 9, color.hasPrefix("#00") { continue }
            var piece: AttributedString = .init(resolve(run.text))
            var font: Font = run.code
                ? .system(size: run.size ?? 12, design: .monospaced)
                : .custom("PCLEnglish", size: run.size ?? 13)
            if run.bold { font = font.bold() }
            if run.italic { font = font.italic() }
            piece.font = font
            if let color = run.color.flatMap(Color.init(hexString:)) {
                piece.foregroundColor = color
            }
            if run.code { piece.backgroundColor = Color.colorGray7 }
            if run.underline { piece.underlineStyle = .single }
            if let link = run.link { piece.link = link }
            result.append(piece)
        }
        return result
    }

    @ViewBuilder
    private func imageView(source: String, height: CGFloat?, width: CGFloat?) -> some View {
        if let url = URL(string: source), let scheme = url.scheme, scheme.hasPrefix("http") {
            NetworkImage(url: url)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            let path: String = source.hasPrefix("file://") ? (URL(string: source)?.path ?? source) : source
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: height)
            }
        }
    }

    // MARK: - 变量

    private func resolve(_ text: String) -> String {
        var result: String = text
        while let range = result.range(of: "\\{variable:([^:}]+):([^}]*)\\}", options: .regularExpression) {
            let token: String = String(result[range])
            let inner: String = String(token.dropFirst("{variable:".count).dropLast())
            let parts: [String] = inner.components(separatedBy: ":")
            let name: String = parts.first ?? ""
            let defaultValue: String = parts.count > 1 ? parts[1] : ""
            result.replaceSubrange(range, with: variables[name] ?? defaultValue)
        }
        result = result.replacingOccurrences(of: "{hint}", with: Self.hints.randomElement() ?? "")
        result = result.replacingOccurrences(of: "{cave}", with: "回声洞暂时没有接入。")
        return result
    }

    // MARK: - 事件

    private func perform(_ events: [HomepageEvent]) {
        for event in events {
            switch event {
            case .openURL(let url):
                NSWorkspace.shared.open(url)
            case .message(let title, let content):
                MessageBoxManager.shared.showText(title: resolve(title), content: resolve(content), level: .info)
            case .refresh:
                onRefresh()
            case .help(let data):
                MessageBoxManager.shared.showText(
                    title: "帮助",
                    content: "这个条目来自 PCL2 的帮助库，本启动器没有内置：\n" + data,
                    level: .info
                )
            case .launch(let name):
                launchInstance(name)
            case .switchPage(let index):
                switchPage(index)
            case .setVariable(let name, let value):
                variables[name] = value
            }
        }
    }

    private func switchPage(_ index: Int) {
        let routes: [AppRoute] = [.launch, .download, .settings, .more]
        guard routes.indices.contains(index) else { return }
        AppRouter.shared.setRoot(routes[index])
    }

    private func launchInstance(_ name: String) {
        Task { @MainActor in
            let repositories: [MinecraftRepository] = LauncherConfig.shared.minecraftRepositories
            guard let repository = repositories.first(where: { $0.id == LauncherConfig.shared.currentRepositoryId })
                    ?? repositories.first else {
                hint("还没有添加任何游戏目录", type: .critical)
                return
            }
            if repository.instances == nil {
                try? await repository.load()
            }
            guard let instance = repository.instance(named: name) else {
                hint("找不到实例 \(name)", type: .critical)
                return
            }
            guard let account = LauncherConfig.shared.accounts.first(where: { $0.id == LauncherConfig.shared.currentAccountId })
                    ?? LauncherConfig.shared.accounts.first else {
                hint("请先登录一个账号", type: .critical)
                return
            }
            AppRouter.shared.setRoot(.launch)
            MinecraftLaunchManager.shared.launch(instance, using: account, in: repository)
        }
    }
}

// MARK: - 映射

private extension HomepageAlignment {
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

private extension HomepageHintTheme {
    var myTipTheme: MyTip.Theme {
        switch self {
        case .blue: .blue
        case .yellow: .yellow
        case .red: .red
        }
    }
}

private extension HomepageButtonStyle {
    var myButtonType: MyButtonType {
        switch self {
        case .normal: .normal
        case .highlight: .highlight
        case .red: .red
        }
    }
}

private extension Color {
    /// "#RRGGBB" / "#AARRGGBB"，或 PCL2 的 brush:N（ColorBrushN）→ 当前主题色。
    init?(hexString: String) {
        let raw: String = hexString.trimmingCharacters(in: .whitespaces)

        if raw.hasPrefix("brush:"), let index = Int(raw.dropFirst("brush:".count)) {
            switch index {
            case 1: self = .color1
            case 2, 3: self = .color3
            case 4: self = .color2
            case 5: self = .color3.opacity(0.7)
            case 6: self = .color3.opacity(0.45)
            case 7: self = .color3.opacity(0.3)
            case 8: self = .color3.opacity(0.18)
            default: return nil
            }
            return
        }

        var value: String = raw
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        guard value.count == 6 || value.count == 8, let number = UInt(value, radix: 16) else { return nil }
        if value.count == 6 {
            self = Color(number)
        } else {
            let alpha: Double = Double((number >> 24) & 0xFF) / 255
            self = Color(number & 0xFFFFFF, alpha: alpha)
        }
    }
}
