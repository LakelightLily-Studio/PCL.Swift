//
//  ChangelogDocument.swift
//  PCL.Swift.Core
//
//  更新日志（CHANGELOG.md）的中间表示与解析。
//
//  格式只支持本仓库实际用到的那一小撮 Markdown：
//    `# 标题`（忽略）、`## 版本`、`### 小节`、`- 条目`，以及 `**加粗**`、反引号代码两种行内标记。
//  不做通用 Markdown 解析——多支持一种语法就多一处会解析错的地方，而这份文件的格式是我们自己定的。
//
//  两个容易踩的点：
//  1. 条目会跨行（中文长句在 80 列处换行），续行必须拼回同一句；
//     中文之间拼接不能补空格（"地址、SHA-256" 会变成 "地址、 SHA-256"）。
//  2. 空行是条目的分隔符，不是内容，遇到就结算上一条。
//

import Foundation

public struct ChangelogDocument: Equatable {
    public var entries: [ChangelogEntry]

    public init(entries: [ChangelogEntry]) {
        self.entries = entries
    }
}

/// 一个版本。
public struct ChangelogEntry: Equatable, Identifiable {
    /// 版本号原文（CHANGELOG.md 的 `## ` 后面那串，例如 `2.0.5`）。
    public var version: String
    public var sections: [ChangelogSection]

    public var id: String { version }

    public init(version: String, sections: [ChangelogSection]) {
        self.version = version
        self.sections = sections
    }
}

/// 版本内的一节（新增 / 改进 / 修复…）。没有小节的日志会得到 title 为空的一节。
public struct ChangelogSection: Equatable {
    public var title: String
    public var items: [ChangelogItem]

    public init(title: String, items: [ChangelogItem]) {
        self.title = title
        self.items = items
    }
}

/// 一条变更。runs 是行内格式拆开后的结果。
public struct ChangelogItem: Equatable {
    public var runs: [ChangelogRun]

    /// 去掉行内标记后的纯文本，用于日志与搜索。
    public var text: String { runs.map(\.text).joined() }

    public init(runs: [ChangelogRun]) {
        self.runs = runs
    }
}

public struct ChangelogRun: Equatable {
    public var text: String
    public var bold: Bool
    /// 反引号包住的行内代码。
    public var code: Bool

    public init(text: String, bold: Bool = false, code: Bool = false) {
        self.text = text
        self.bold = bold
        self.code = code
    }
}

public enum ChangelogParser {
    public static func parse(_ markdown: String) -> ChangelogDocument {
        var entries: [ChangelogEntry] = []
        var entry: ChangelogEntry?
        var section: ChangelogSection?
        var itemLines: [String] = []

        /// 结算当前条目（含续行）。
        func commitItem() {
            guard !itemLines.isEmpty else { return }
            let text: String = joinSoftWrapped(itemLines)
            itemLines.removeAll()
            guard var currentSection = section else { return }
            currentSection.items.append(.init(runs: inlineRuns(text)))
            section = currentSection
        }

        /// 结算当前小节。没有条目的小节（只有标题）不产出。
        func commitSection() {
            commitItem()
            guard let currentSection = section, !currentSection.items.isEmpty else {
                section = nil
                return
            }
            guard var currentEntry = entry else {
                section = nil
                return
            }
            currentEntry.sections.append(currentSection)
            entry = currentEntry
            section = nil
        }

        /// 结算当前版本。只有标题、没有任何条目的版本不产出——渲染出来会是一张空卡片。
        func commitEntry() {
            commitSection()
            guard let currentEntry = entry, !currentEntry.sections.isEmpty else {
                entry = nil
                return
            }
            entries.append(currentEntry)
            entry = nil
        }

        for rawLine in markdown.split(whereSeparator: \.isNewline) {
            let line: String = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                commitItem()
                continue
            }
            if line.hasPrefix("### ") {
                commitItem()
                commitSection()
                section = .init(title: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces), items: [])
                continue
            }
            if line.hasPrefix("## ") {
                commitItem()
                commitSection()
                commitEntry()
                entry = .init(version: String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), sections: [])
                continue
            }
            if line.hasPrefix("# ") {
                // 文档大标题（"更新日志"），没有渲染价值。
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                commitItem()
                if section == nil { section = .init(title: "", items: []) }
                itemLines = [String(line.dropFirst(2))]
                continue
            }
            // 续行：只有正在累积条目时才有意义，其它位置（导语、说明）一律丢掉。
            if !itemLines.isEmpty {
                itemLines.append(line)
            }
        }
        commitEntry()

        return .init(entries: entries)
    }

    // MARK: - 续行拼接

    /// 把一条变更的软换行拼回一句话。
    ///
    /// 中文之间不能补空格（"地址、" + "SHA-256" 拼成 "地址、SHA-256"），
    /// 西文之间必须补（"the" + "launcher" 拼成 "the launcher"），
    /// 中文与西文 / 代码交界处补一个（"退回" + 反引号包住的 Pictures/ 拼成 "退回 Pictures/"）。
    private static func joinSoftWrapped(_ lines: [String]) -> String {
        var result: String = ""
        for line in lines {
            let piece: String = line.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if result.isEmpty {
                result = piece
                continue
            }
            result += needsSpace(between: result.last, and: piece.first) ? " " + piece : piece
        }
        return result
    }

    private static func needsSpace(between previous: Character?, and next: Character?) -> Bool {
        guard let previous, let next else { return false }
        // 中文标点后面不补："地址、" + "SHA-256" 拼成 "地址、SHA-256"。
        if isCJKPunctuation(previous) { return false }
        // 两侧都是中文（含标点）不补。
        if isCJK(previous) && isCJK(next) { return false }
        // 其余交界都补一个空格，与 GitHub 渲染软换行的效果一致。
        return true
    }

    private static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F,   // CJK 标点（、。「」）
             0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0xFF00...0xFFEF,   // 全角标点与字母
             0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    /// 只认中日韩标点（不含汉字）。
    private static func isCJKPunctuation(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F, 0xFF01...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65:
            return true
        default:
            return false
        }
    }

    // MARK: - 行内格式

    /// 拆出加粗与反引号代码两种行内标记。
    ///
    /// 标记不成对时按"从这里开始生效"处理，不抛错也不回滚：
    /// 更新日志是展示内容，为了一处漏写的星号让整页消失不值得。
    private static func inlineRuns(_ text: String) -> [ChangelogRun] {
        var runs: [ChangelogRun] = []
        var buffer: String = ""
        var bold: Bool = false
        var code: Bool = false

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(.init(text: buffer, bold: bold, code: code))
            buffer = ""
        }

        var index: String.Index = text.startIndex
        while index < text.endIndex {
            let rest: Substring = text[index...]
            if rest.hasPrefix("**") {
                flush()
                bold.toggle()
                index = text.index(index, offsetBy: 2)
                continue
            }
            if rest.hasPrefix("`") {
                flush()
                code.toggle()
                index = text.index(after: index)
                continue
            }
            buffer.append(text[index])
            index = text.index(after: index)
        }
        flush()

        return runs.isEmpty ? [.init(text: text)] : runs
    }
}
