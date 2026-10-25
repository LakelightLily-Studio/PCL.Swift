//
//  MemoryAllocation.swift
//  PCL.Swift.Core
//
//  设置 → 启动 →「内存分配」的纯计算部分：自动配置的推荐值、自定义滑杆的
//  取整映射，以及内存条要用的系统内存读数。
//
//  数值全部取自 PCL2：自动配置的四个阶段来自 PageSetupLaunch.GetRam，
//  滑杆映射来自同一个函数里的手动配置分支（0…49 分段线性）。
//

import Foundation
import Darwin

/// 内存分配方式。
public enum MemoryAllocationMode: String, Codable, CaseIterable, CustomStringConvertible {
    /// 根据当前可用内存动态决定分配量。
    case automatic
    /// 由用户用滑杆指定。
    case custom

    public var description: String {
        switch self {
        case .automatic: "自动配置"
        case .custom: "自定义"
        }
    }
}

public enum MemoryAllocation {
    /// 滑杆的最大刻度（PCL2 的 SliderRamCustom.MaxValue）。
    public static let maximumSliderPosition: Int = 49

    // MARK: - 系统内存

    /// 物理内存总量（字节）。
    public static var physicalBytes: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 当前可用内存（字节），按 free + inactive + speculative 计。
    ///
    /// 不用 "wired + compressed" 反推：macOS 的 inactive 页随时可以被回收，
    /// 这才是"还能给新进程用多少"的近似值，与 PCL2 取 AvailablePhysicalMemory 的意图一致。
    /// 取不到 VM 统计时退回总量的一半——宁可给一个保守值，也不要让
    /// 自动配置算出 0。
    public static var availableBytes: UInt64 {
        guard let statistics = vmStatistics(), let pageSize = pageSize else {
            return physicalBytes / 2
        }
        let pages: UInt64 = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        return min(pages * pageSize, physicalBytes)
    }

    /// 已被占用的内存（字节）。
    public static var usedBytes: UInt64 {
        physicalBytes &- availableBytes
    }

    // MARK: - 自动配置

    /// 自动配置的推荐值（GB，保留一位小数）。
    ///
    /// - Parameters:
    ///   - availableGigabytes: 可用内存，默认取 `availableBytes`。
    ///   - modCount: 实例 mods 目录下的 Mod 数量。
    ///   - modable: 实例是否能装 Mod（决定按哪档目标值算）。
    public static func recommendedGigabytes(
        availableGigabytes: Double? = nil,
        modCount: Int = 0,
        modable: Bool = false
    ) -> Double {
        var remaining: Double = availableGigabytes ?? (Double(availableBytes) / 1_073_741_824)
        let minimum: Double
        let target1: Double
        let target2: Double
        let target3: Double
        if modable {
            let count: Double = Double(modCount)
            minimum = 0.5 + count / 150
            target1 = 1.5 + count / 90
            target2 = 2.7 + count / 50
            target3 = 4.5 + count / 25
        } else {
            minimum = 0.5
            target1 = 1.5
            target2 = 2.5
            target3 = 4
        }

        var given: Double = 0
        // 阶段一：0 ~ T1，全给。
        given += min(remaining, target1)
        remaining -= target1

        // 阶段二：T1 ~ T2，只给剩余空间的 70%。
        if remaining >= 0.1 {
            let delta: Double = target2 - target1
            given += min(remaining * 0.7, delta)
            remaining -= delta / 0.7
        }
        // 阶段三：T2 ~ T3，40%。
        if remaining >= 0.1 {
            let delta: Double = target3 - target2
            given += min(remaining * 0.4, delta)
            remaining -= delta / 0.4
        }
        // 阶段四：T3 之外只再给 15%，避免把系统内存吃干。
        if remaining >= 0.1 {
            given += min(remaining * 0.15, target3)
        }
        return (max(given, minimum) * 10).rounded() / 10
    }

    // MARK: - 自定义滑杆

    /// 滑杆刻度对应的分配量（GB）。
    ///
    /// 分段线性，低段细、高段粗：绝大多数人落在 1…8 GB，刻度太粗就没法微调。
    public static func gigabytes(forSliderPosition position: Int) -> Double {
        let clamped: Int = min(max(position, 0), maximumSliderPosition)
        switch clamped {
        case ...12: return 0.3 + Double(clamped) * 0.1
        case ...25: return 1.5 + Double(clamped - 12) * 0.5
        case ...33: return 8 + Double(clamped - 25)
        default: return 16 + Double(clamped - 33) * 2
        }
    }

    /// 分配量（GB）落回哪个刻度。取最接近的刻度，保证界面显示与真实值一致。
    public static func sliderPosition(forGigabytes gigabytes: Double) -> Int {
        var best: Int = 0
        var bestDistance: Double = .infinity
        for position in 0...maximumSliderPosition {
            let distance: Double = abs(self.gigabytes(forSliderPosition: position) - gigabytes)
            if distance < bestDistance {
                best = position
                bestDistance = distance
            }
        }
        return best
    }

    /// 滑杆刻度对应的 MB 数（启动参数用的是整数 MB）。
    public static func megabytes(forSliderPosition position: Int) -> UInt64 {
        UInt64((gigabytes(forSliderPosition: position) * 1024).rounded())
    }

    // MARK: - 系统调用

    private static func vmStatistics() -> vm_statistics64? {
        var statistics: vm_statistics64 = .init()
        var count: mach_msg_type_number_t = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? statistics : nil
    }

    private static let pageSize: UInt64? = {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS else { return nil }
        return UInt64(size)
    }()
}
