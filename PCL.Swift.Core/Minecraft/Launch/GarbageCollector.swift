//
//  GarbageCollector.swift
//  PCL.Swift.Core
//
//  设置 → 启动 → 高级选项 →「内存管理」的垃圾回收器选项与对应的 JVM 参数。
//
//  选项与文案对齐 PCL2（Pages/PageSetup/PageSetupLaunch.xaml 的 LaunchAdvanceGC），
//  参数的派生方式参考 Swift-Craft-Launcher：配置里只存枚举，真正开跑时再生成参数，
//  不去反解析用户手里的字符串（那边 parseExistingJvmArguments 就是这种脆弱设计的补丁）。
//
//  与 Swift-Craft-Launcher 最大的差异在这里：那边把 GC 参数插在命令最前面，而
//  清单自带的 -XX:+UseG1GC 排在其后，于是用户选 ZGC 会被清单覆盖。这里改成
//  先把清单与自定义参数里由本启动器管理的 GC 参数全部剔除，再追加一套，
//  JVM 只可能看到一套 GC 开关。
//

import Foundation

/// 垃圾回收器的策略。
///
/// rawValue 对齐 PCL2 的 LaunchAdvanceGC（0/1/2/3/4），写进 config.json 后
/// 不能改名——老配置里存的是整数。
public enum GarbageCollectorMode: Int, Codable, CaseIterable, CustomStringConvertible {
    /// Java 21+ 用分代 ZGC，15…20 用非分代 ZGC，14- 用 G1GC。
    case autoZGC = 0
    /// Java 21+ 用分代 ZGC，20- 用 G1GC。
    case generationalZGC = 1
    /// 总是使用 G1GC，附带 Mojang 官方的参数。
    case g1 = 2
    /// 总是使用 G1GC，附带 PCL 调优过的参数。
    case tunedG1 = 4
    /// 不指定，完全交给用户自己写的 JVM 参数。
    case unspecified = 3

    public var description: String {
        switch self {
        case .autoZGC: "尽量使用 ZGC"
        case .generationalZGC: "尽量使用分代 ZGC"
        case .g1: "标准 G1GC"
        case .tunedG1: "调优 G1GC"
        case .unspecified: "不指定（可自定义）"
        }
    }

    /// 下拉列表里的显示顺序。
    ///
    /// 不能直接用 allCases：枚举按 rawValue 排列，而 PCL2 的列表把
    /// 「不指定」放在最后、把「调优 G1GC」（rawValue 4）放在它前面。
    public static var menuOrder: [GarbageCollectorMode] {
        [.autoZGC, .generationalZGC, .g1, .tunedG1, .unspecified]
    }

    /// 这个策略在当前 Java 上最终会落到哪一类回收器。
    public func resolved(isG1GCUsing javaMajorVersion: Int) -> Bool {
        switch self {
        case .autoZGC: javaMajorVersion < 15
        case .generationalZGC: javaMajorVersion < 21
        case .g1, .tunedG1: true
        case .unspecified: true
        }
    }
}

/// GC 参数的生成本与过滤。
public enum GarbageCollectorArguments {
    /// 由本启动器接管的 GC 参数（PCL2 的 ModLaunch.vb 里同一条正则）。
    ///
    /// 覆盖 GC 开关本身（-XX:+UseG1GC / -XX:+UseZGC …）、分代 ZGC 开关、
    /// 紧凑对象头，以及 G1 的堆分区与空闲比例调参。用户自己写的
    /// -XX:MaxGCPauseMillis 之类也会被视作"该由内存管理接管"而被替换——
    /// 这是 PCL2 的行为：选了内存管理，就不该再有两套参数打架。
    private static let managedPattern: String =
        #"-XX:[+-]?(Use\w+GC|ZGenerational|UseCompactObjectHeaders|G1\w+Percent|G1\w+Size|(Max|Min)(GCPauseMillis|HeapFreeRatio))"#

    /// 该参数是否由本启动器接管。
    public static func isManaged(_ argument: String) -> Bool {
        argument.range(of: managedPattern, options: .regularExpression) != nil
    }

    /// 剔除全部由本启动器接管的参数，其余保持原顺序。
    public static func removingManagedArguments(from arguments: [String]) -> [String] {
        arguments.filter { !isManaged($0) }
    }

    /// 按策略与 Java 版本生成参数。
    ///
    /// 顺序与 PCL2 完全一致：先 UnlockExperimentalVMOptions（ZGC 在 15…20
    /// 仍属实验特性，不解锁会直接起不来），Java 24+ 再补紧凑对象头，最后才是
    /// GC 开关与调参。
    ///
    /// - Parameters:
    ///   - mode: 用户选择的策略。
    ///   - javaMajorVersion: 本次启动所用 Java 的大版本号。
    public static func arguments(for mode: GarbageCollectorMode, javaMajorVersion: Int) -> [String] {
        guard mode != .unspecified else { return [] }

        var arguments: [String] = ["-XX:+UnlockExperimentalVMOptions"]
        if javaMajorVersion >= 24 {
            arguments.append("-XX:+UseCompactObjectHeaders")
        }

        if mode.resolved(isG1GCUsing: javaMajorVersion) {
            arguments.append(contentsOf: g1Arguments(tuned: mode == .tunedG1, javaMajorVersion: javaMajorVersion))
        } else {
            arguments.append("-XX:+UseZGC")
            // Java 23 起默认就是分代 ZGC，再加这个参数反而会报重复。
            if javaMajorVersion == 21 || javaMajorVersion == 22 {
                arguments.append("-XX:+ZGenerational")
            }
        }
        return arguments
    }

    /// G1GC 的参数。tuned 为 true 时在官方参数之外补 PCL 的调优项。
    private static func g1Arguments(tuned: Bool, javaMajorVersion: Int) -> [String] {
        var arguments: [String] = [
            "-XX:+UseG1GC",
            "-XX:G1NewSizePercent=20",
            "-XX:G1ReservePercent=20",
            "-XX:G1HeapRegionSize=32M",
            "-XX:MaxGCPauseMillis=50"
        ]
        if javaMajorVersion <= 7 {
            // PermGen 在 Java 8 才被移除，7 及更老的版本必须显式给大小。
            arguments.append("-XX:MaxPermSize=512m")
        }
        guard tuned else { return arguments }
        if javaMajorVersion == 8 {
            arguments.append("-XX:+ParallelRefProcEnabled")
        }
        if javaMajorVersion >= 12 {
            // 这两个比例必须满足 Min < G1NewSizePercent，否则 G1 会自己纠正，
            // 用户看到的设置与实际不符。
            arguments.append("-XX:MinHeapFreeRatio=25")
            arguments.append("-XX:MaxHeapFreeRatio=40")
        }
        return arguments
    }
}
