//
//  ResourceFileName.swift
//  PCL.Swift.Core
//

import Foundation

/// 「文件名格式」的设置实现：把模板渲染成实际落盘的文件名。
///
/// PCL2 的默认格式是 [译名] 名称-版本；本启动器还没有译名数据源，所以只提供
/// 名称/版本/加载器/类型四个占位符，{name} 就是资源本身的名字。
/// 规则集中在这里，下载点只调用 format，不要各自拼字符串。
public enum ResourceFileName {
    /// 默认模板：名称-版本，例如 sodium-0.6.13。
    public static let defaultTemplate: String = "{name}-{version}"

    /// 模板里支持的占位符（界面上按这个顺序提示用户）。
    public static let placeholders: [String] = ["{name}", "{version}", "{loader}", "{type}"]

    /// 渲染模板。
    /// - Parameters:
    ///   - template: 用户填写的模板。
    ///   - name: 资源名称。
    ///   - version: 版本号，可为 nil。
    ///   - loader: 模组加载器，可为 nil。
    ///   - type: 资源类型。
    ///   - fileExtension: 原始扩展名（不含点），结果一定会带上它。
    ///   - fallback: 模板渲染不出可用名字时使用的原名。
    /// - Returns: 可以直接拼进目录的文件名。
    public static func format(
        template: String,
        name: String,
        version: String?,
        loader: ModLoader?,
        type: ResourceType,
        fileExtension: String,
        fallback: String
    ) -> String {
        var result: String = template
        let values: [String: String] = [
            "{name}": name,
            "{version}": version ?? "",
            "{loader}": loader?.rawValue ?? "",
            // Core 拿不到 App 层的本地化名称，这里用原始类型名（mod / resourcepack…）。
            "{type}": type.rawValue
        ]
        for (token, value) in values {
            result = result.replacingOccurrences(of: token, with: value)
        }

        result = sanitize(result)
        guard !result.isEmpty else { return sanitize(fallback) }

        let ext: String = fileExtension.hasPrefix(".") ? String(fileExtension.dropFirst()) : fileExtension
        if !ext.isEmpty, !result.lowercased().hasSuffix("." + ext.lowercased()) {
            result += "." + ext
        }
        return result
    }

    /// 去掉路径分隔符、合并重复分隔符，并裁掉首尾的连接符。
    static func sanitize(_ raw: String) -> String {
        var text: String = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 形如 [译名] {name} 的模板在缺值时只剩一对空括号，先整体删掉，
        // 否则会得到 "[] Sodium" 这种明显不像文件名的结果。
        for pair in ["[]", "()", "{}", "（）", "【】"] {
            while text.contains(pair) {
                text = text.replacingOccurrences(of: pair, with: "")
            }
        }
        // 版本号缺失时会留下 "名称--" 之类的残骸：反复折叠到稳定为止。
        while text.contains("--") {
            text = text.replacingOccurrences(of: "--", with: "-")
        }
        let separators: CharacterSet = CharacterSet(charactersIn: "-_ .")
        while let first = text.first, first.unicodeScalars.allSatisfy(separators.contains) {
            text.removeFirst()
        }
        while let last = text.last, last.unicodeScalars.allSatisfy(separators.contains) {
            text.removeLast()
        }
        return text
    }
}
