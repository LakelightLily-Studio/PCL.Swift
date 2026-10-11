//
//  ByteFormat.swift
//  PCL.Mac
//

import Foundation

public enum ByteFormat {
    /// 把字节数格式化为带单位的可读文本，每 1024 进一位，最多保留到 TB。
    /// - Parameters:
    ///   - bytes: 字节数。
    ///   - perSecond: 为真时单位带上 `/s` 后缀（用于速度显示）。
    public static func string(_ bytes: Int64, perSecond: Bool = false) -> String {
        let suffixes: [String] = perSecond ? ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"] : ["B", "KB", "MB", "GB", "TB"]
        var value: Double = .init(bytes)
        var unitIndex: Int = 0

        while value >= 1024 && unitIndex < suffixes.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        let formatted: String = .init(format: value < 10 && unitIndex > 0 ? "%.1f" : "%.0f", value)
        return "\(formatted) \(suffixes[unitIndex])"
    }
}
