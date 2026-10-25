//
//  CurseforgeAPIKeyResolver.swift
//  PCL.Swift.Core
//

import Foundation

/// 决定「这一次该用哪个 CurseForge API Key」。
///
/// CurseForge 的接口要求每个调用方自带 Key，而 Key 的来源有好几层：
/// 用户在设置里手填的、打包进 App 的（CI 注入的 Secrets.properties）、
/// 以及本地开发用的环境变量。层级一旦分散到各处的空字符串兜底里就会漂移——
/// 之前正是这样在没配 Key 的构建里造出了「空 Key」客户端，请求一律 401/403，
/// 用户看到的却是另一套文案（Issue #4）。
///
/// 这里只做纯逻辑，不做 IO：调用方负责把各自的来源读进来。
public enum CurseforgeAPIKeyResolver {
    /// 解析最终生效的 Key。
    ///
    /// 顺序：用户手填 → 内置（Secrets.properties / 环境变量）。
    /// 空白串（含只有空格、只有换行）一律视为「没填」，这样用户清空输入框
    /// 就能回到内置 Key，而不是得到一个必然被拒的空 Key。
    /// - Parameters:
    ///   - userProvided: 用户在设置里填写的 Key，可以为 nil。
    ///   - bundled: 打包进 App 或由环境变量给出的 Key，可以为 nil。
    /// - Returns: 去掉首尾空白后的 Key；两者都没有有效值时返回 nil。
    public static func resolve(userProvided: String?, bundled: String?) -> String? {
        normalized(userProvided) ?? normalized(bundled)
    }

    /// 去掉首尾空白与包裹的引号；空白串返回 nil。
    public static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed: String = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 用户从网页或聊天记录里复制 Key 时常把引号一起带进来，
        // 这样的 Key 拿去请求必然被拒，先剥掉再判断是否为空。
        while trimmed.count >= 2,
              let first = trimmed.first, let last = trimmed.last,
              (first == "\"" || first == "'"), first == last {
            trimmed = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
