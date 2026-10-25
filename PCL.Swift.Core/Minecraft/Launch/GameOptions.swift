//
//  GameOptions.swift
//  PCL.Swift.Core
//
//  启动前对实例 options.txt 的修改。
//
//  目前只有一条：把游戏语言设成中文（设置 → 其他 → 辅助功能）。
//  做法对齐 PCL2 的 ModLaunch：只有在玩家没手动选过语言（options.txt 里没有 lang）
//  或还没有存档时才改写，避免把玩家自己在游戏里调好的语言覆盖掉。
//

import Foundation

public enum GameOptions {
    public static let optionsFileName: String = "options.txt"

    /// 把 options.txt 里的 lang 改成指定语言。
    ///
    /// - Parameters:
    ///   - language: 目标语言。1.10 及更早的版本要写 zh_CN，1.11 起写 zh_cn。
    ///   - directory: 实例目录（与 .minecraft 等价的目录）。
    ///   - onlyWhenUntouched: 只在玩家没动过语言（或还没有存档）时改写。
    /// - Returns: 是否真的写了盘。
    @discardableResult
    public static func setLanguage(
        _ language: String,
        at directory: URL,
        onlyWhenUntouched: Bool
    ) throws -> Bool {
        let url: URL = directory.appending(path: optionsFileName)
        let hasSaves: Bool = FileManager.default.fileExists(atPath: directory.appending(path: "saves").path)

        var lines: [String] = []
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let text: String = try String(contentsOf: url, encoding: .utf8)
                lines = text.components(separatedBy: "\n")
            } catch {
                // 老版本游戏的 options.txt 可能不是 UTF-8。读不出来就不动它，
                // 用 UTF-8 重写只会把玩家的设置写坏。
                log("读取 options.txt 失败，跳过语言设置：\(error.localizedDescription)")
                return false
            }
        }

        let langIndex: Int? = lines.firstIndex { $0.hasPrefix("lang:") }
        let current: String? = langIndex.map { String(lines[$0].dropFirst("lang:".count)) }

        if onlyWhenUntouched, current != nil, hasSaves {
            return false
        }
        if current == language {
            return false
        }

        if let langIndex {
            lines[langIndex] = "lang:\(language)"
        } else {
            lines.append("lang:\(language)")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
