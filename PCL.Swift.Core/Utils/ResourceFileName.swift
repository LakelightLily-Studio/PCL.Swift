//
//  ResourceFileName.swift
//  PCL.Swift.Core
//

import Foundation

/// 「文件名格式」的设置实现：把项目名与原始文件名拼成落盘文件名。
///
/// 规则照 PCL2 的 PageDownloadCompDetail（ToolDownloadTranslateV2）：
/// 有译名时按五种样式之一把译名缀在原始文件名前后，没有译名时原样使用文件名。
/// 本启动器还没有译名数据源，所以这里的「译名」取项目标题（project.title）——
/// 它等于文件名主干时视为没有译名，直接沿用原始文件名，与原版的判断一致。
///
/// 规则集中在这里，下载点只调用 format，不要各自拼字符串。
public enum ResourceFileName {
    /// 文件名格式，取值与原版下拉框的五个选项一一对应。
    public enum Format: String, Codable, CaseIterable, Sendable, CustomStringConvertible {
        /// 【译名】文件名
        case bracketCN
        /// [译名] 文件名（原版默认）
        case bracketSquare
        /// 译名-文件名
        case prefixDash
        /// 文件名-译名
        case suffixDash
        /// 只用原始文件名
        case plain

        /// 下拉框里显示的示例文案，与原版一致。
        public var description: String {
            switch self {
            case .bracketCN: "【机械动力】create-1.21.1-6.0.4"
            case .bracketSquare: "[机械动力] create-1.21.1-6.0.4"
            case .prefixDash: "机械动力-create-1.21.1-6.0.4"
            case .suffixDash: "create-1.21.1-6.0.4-机械动力"
            case .plain: "create-1.21.1-6.0.4"
            }
        }
    }

    /// 新配置的默认格式，与 PCL2 的 ToolDownloadTranslateV2 默认值（1）一致。
    public static let defaultFormat: Format = .bracketSquare

    /// 渲染文件名。
    /// - Parameters:
    ///   - format: 用户选择的格式。
    ///   - name: 项目标题（没有译名数据源时它就是显示名）。
    ///   - originalName: 资源源站给出的原始文件名，含扩展名。
    ///   - type: 资源类型，Mod 要额外处理 `~`（Mixin 会因此加载失败）。
    /// - Returns: 可以直接拼进目录的文件名。
    public static func format(
        format: Format,
        name: String,
        originalName: String,
        type: ResourceType
    ) -> String {
        let original: String = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return sanitize(name) }

        let stem: String = (original as NSString).deletingPathExtension
        let translated: String = sanitize(name)
        // 没有译名（或名字就是文件名主干）时保持原样，原版也是这么判断的。
        var result: String
        if translated.isEmpty || translated == stem || format == .plain {
            result = original
        } else {
            switch format {
            case .bracketCN: result = "【\(translated)】\(original)"
            case .bracketSquare: result = "[\(translated)] \(original)"
            case .prefixDash: result = "\(translated)-\(original)"
            case .suffixDash: result = "\(original)-\(translated)"
            case .plain: result = original
            }
        }
        // ~ 会让 Mixin 加载失败（原版同样的处理）。
        if type == .mod {
            result = result.replacingOccurrences(of: "~", with: "-")
        }
        return result
    }

    /// 把译名里的非法字符换成全角，规则照抄原版：Windows 上的非法字符换成全角，
    /// 双引号直接删掉，"： " 这种带空格的冒号压成 "："。
    static func sanitize(_ raw: String) -> String {
        var text: String = raw
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\\", with: "＼")
            .replacingOccurrences(of: "/", with: "／")
            .replacingOccurrences(of: "|", with: "｜")
            .replacingOccurrences(of: ":", with: "：")
            .replacingOccurrences(of: "<", with: "＜")
            .replacingOccurrences(of: ">", with: "＞")
            .replacingOccurrences(of: "*", with: "＊")
            .replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "： ", with: "：")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 形如 "名称 (作者)" 的标题只取括号前的部分，原版同样是 BeforeFirst(" (")。
        for separator in [" (", " - "] {
            if let range = text.range(of: separator) {
                text = String(text[text.startIndex..<range.lowerBound])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
