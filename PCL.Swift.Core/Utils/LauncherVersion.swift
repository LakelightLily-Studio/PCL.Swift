//
//  LauncherVersion.swift
//  PCL.Swift.Core
//

import Foundation

/// 启动器营销版本号的解析与比较。
///
/// 更新渠道换成 GitHub Release 之后，版本只剩 tag（v2.0.1）而没有
/// CFBundleVersion 那种单调递增的构建号，所以比较必须落在营销版本上。
/// 解析规则刻意宽松：允许 v 前缀、预发布后缀（-beta.2）、不足三段（2.0 视作 2.0.0）。
public enum LauncherVersion {
    /// 把 "v2.0.1" / "2.0" / "2.0.1-beta.2" 解析成三段整数。
    ///
    /// - Returns: 解析失败返回 nil（例如 tag 是 "nightly" 这种非版本号）。
    public static func components(of raw: String) -> [Int]? {
        var text: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        // 预发布与构建元数据不参与比较：2.0.1-beta.2 在本启动器里就当作 2.0.1。
        for separator in ["-", "+"] {
            if let range = text.range(of: separator) {
                text = String(text[..<range.lowerBound])
            }
        }

        let parts: [String] = text.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }

        var numbers: [Int] = []
        numbers.reserveCapacity(parts.count)
        for part in parts {
            // 非纯数字一律判失败：与其拿 "1rc" 猜出一个版本号，不如放弃这次比较。
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        return Array(numbers.prefix(3))
    }

    /// - Returns: candidate 是否比 current 新。
    ///
    /// 任何一边解析失败都返回 false：宁可漏掉一次更新提示，
    /// 也不要拿无法比较的 tag 去劝用户升级。
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let lhs = components(of: candidate), let rhs = components(of: current) else {
            return false
        }
        for index in 0..<max(lhs.count, rhs.count) {
            let left: Int = index < lhs.count ? lhs[index] : 0
            let right: Int = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}
