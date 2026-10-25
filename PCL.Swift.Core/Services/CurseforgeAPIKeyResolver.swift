//
//  CurseforgeAPIKeyResolver.swift
//  PCL.Swift.Core
//

import Foundation

/// 决定「这一次该用哪个 CurseForge API Key」。
///
/// CurseForge 的接口要求每个调用方自带 Key。Key 只有内置一层（打包进 App 的
/// Secrets.properties 或本地开发用的环境变量），用户侧没有手填入口了。
/// 空字符串兜底曾经造出过必然 401 的客户端，所以这里把「空」统一判成「没有」，
/// 解析只有这一处实现（Issue #4）。
///
/// 这里只做纯逻辑，不做 IO：调用方负责把各自的来源读进来。
public enum CurseforgeAPIKeyResolver {
    /// 解析最终生效的 Key。
    ///
    /// 顺序：环境变量（本地开发覆盖）→ 打包进 App 的 Key。
    /// 空白串（含只有空格、只有换行）一律视为「没有」，不返回空 Key。
    /// - Parameters:
    ///   - userProvided: 优先级更高的来源（目前是环境变量），可以为 nil。
    ///   - bundled: 打包进 App 的 Key，可以为 nil。
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
