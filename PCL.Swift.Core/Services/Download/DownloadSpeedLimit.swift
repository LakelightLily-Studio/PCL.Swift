//
//  DownloadSpeedLimit.swift
//  PCL.Swift.Core
//
//  「设置 → 其他 → 下载 → 速度限制」滑杆的刻度换算。
//
//  刻度与文案取自 PCL2（PageSetupSystem.xaml.vb 的 SliderDownloadSpeed.GetHintText）：
//  0…14 每格 0.1 MB/s，15…31 每格 0.5 MB/s，32…41 每格 1 MB/s，42 为不限制。
//  低段细、高段粗，避免为了 100 KB/s 的差别去拖一整条滑杆。
//

import Foundation

public enum DownloadSpeedLimit {
    /// 滑杆的最大刻度，同时也是「不限制」。
    public static let maximumSliderPosition: Int = 42

    /// 刻度对应的速度（字节/秒）。0 表示不限制。
    public static func bytesPerSecond(forSliderPosition position: Int) -> Int64 {
        let value: Int = min(max(position, 0), maximumSliderPosition)
        switch value {
        case ...14:
            return Int64(Double(value + 1) * 0.1 * 1024 * 1024)
        case ...31:
            return Int64(Double(value - 11) * 0.5 * 1024 * 1024)
        case ...41:
            return Int64(value - 21) * 1024 * 1024
        default:
            return 0
        }
    }

    /// 速度（字节/秒）落回最接近的刻度。
    public static func sliderPosition(forBytesPerSecond bytesPerSecond: Int64) -> Int {
        guard bytesPerSecond > 0 else { return maximumSliderPosition }
        var best: Int = maximumSliderPosition
        var bestDistance: Int64 = .max
        for position in 0...maximumSliderPosition {
            let distance: Int64 = abs(self.bytesPerSecond(forSliderPosition: position) - bytesPerSecond)
            if distance < bestDistance {
                best = position
                bestDistance = distance
            }
        }
        return best
    }

    /// 刻度对应的提示文案，与 PCL2 的滑杆提示一致。
    public static func description(forSliderPosition position: Int) -> String {
        let value: Int = min(max(position, 0), maximumSliderPosition)
        switch value {
        case maximumSliderPosition:
            return "无限制"
        case ...14:
            return String(format: "%.1f MB/s", Double(value + 1) * 0.1)
        case ...31:
            return String(format: "%.1f MB/s", Double(value - 11) * 0.5)
        default:
            return "\(value - 21) MB/s"
        }
    }
}
