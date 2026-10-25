//
//  LaunchEnums.swift
//  PCL.Swift.Core
//
//  启动相关的枚举。
//
//  放在 Core 而不是 App：LauncherConfig（全局默认值）与 MinecraftInstance.Config
//  （实例覆盖值）都要引用它们，两边都 import Core。如果定义在 App 里，
//  Core 的实例配置就没法表达"跟随全局"的三态。
//

import Foundation

/// 游戏窗口模式。
public enum GameWindowType: String, Codable, CaseIterable, CustomStringConvertible {
    /// 交给游戏自己决定（通常为 854×480 窗口）。
    case standard
    /// 全屏。
    case fullscreen
    /// 使用自定义宽高。
    case custom

    public var description: String {
        switch self {
        case .standard: "默认"
        case .fullscreen: "全屏"
        case .custom: "自定义"
        }
    }
}

/// 启动器可见性。
public enum LauncherVisibility: String, Codable, CaseIterable, CustomStringConvertible {
    /// 启动游戏后关闭启动器。
    case close
    /// 启动游戏后隐藏启动器。
    case hide
    /// 启动游戏后最小化启动器。
    case minimize
    /// 保持可见。
    case keepVisible

    public var description: String {
        switch self {
        case .close: "启动后关闭启动器"
        case .hide: "启动后隐藏启动器"
        case .minimize: "启动后最小化启动器"
        case .keepVisible: "保持可见"
        }
    }
}

public extension LauncherVisibility {
    /// 解析最终生效的可见性：实例设置优先，未设置时跟随全局。
    ///
    /// 放在 Core 里是因为它只依赖配置值，与 UI 无关；
    /// 启动流程与启动器窗口两侧都要按同一套规则判断。
    static func resolve(instance: MinecraftInstance?) -> LauncherVisibility {
        if let override = instance?.config.launcherVisibility { return override }
        return LauncherConfigDefaults.launcherVisibility
    }
}

/// 全局默认值的只读入口。
///
/// Core 不能直接引用 App 层的 LauncherConfig，但启动流程需要读全局默认值。
/// 由 App 在启动时把值灌进来，Core 只读不写。
public enum LauncherConfigDefaults {
    /// 全局默认启动器可见性。
    public static var launcherVisibility: LauncherVisibility = .keepVisible
    /// 全局默认进程优先级。
    public static var processPriority: ProcessPriority = .normal
    /// 全局优先使用的 Java（设置 → 启动 → 高级选项 → Java 列表）。
    ///
    /// nil 表示自动选择：仍由 JavaSearcher 按版本挑。实例自己指定过 Java 时不看这个值。
    public static var preferredJavaURL: URL?
}

/// 游戏进程优先级。
public enum ProcessPriority: String, Codable, CaseIterable, CustomStringConvertible {
    case high, normal, low

    public var description: String {
        switch self {
        case .high: "高"
        case .normal: "中"
        case .low: "低"
        }
    }
}
