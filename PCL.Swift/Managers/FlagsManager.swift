//
//  FlagsManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/14.
//

import Foundation
import Core

class FlagsManager: ObservableObject {
    private static var _shared: FlagsManager?

    /// 全局实例。必须在启动阶段由 `AppDelegate` 注入后才能访问：
    /// 早于注入访问会立刻在注入点给出可定位的失败，而不是在某个随机调用点崩溃。
    public static var shared: FlagsManager {
        guard let instance = _shared else {
            fatalError("FlagsManager.shared 在注入之前被访问，请检查 AppDelegate 的初始化顺序。")
        }
        return instance
    }

    public static func install(_ instance: FlagsManager) {
        // 先发布实例再应用开关：`applyChange` 可能回调到读取 `shared` 的地方
        // （例如关闭联机开关时让路由退出联机页）。
        _shared = instance
        instance.applyAllFlags()
    }
    @Published private(set) var enabledFlags: Set<FeatureFlag>
    private let defaultFlags = Set<FeatureFlag>(arrayLiteral: .deduplicateLibraries)
    
    init(enabledFlags: Set<FeatureFlag>?) {
        if let enabledFlags {
            self.enabledFlags = enabledFlags
        } else {
            self.enabledFlags = defaultFlags
        }
    }
    
    /// 把当前开关状态同步到各消费点。
    /// 由 `install(_:)` 在实例发布之后调用，不能放进 `init`。
    func applyAllFlags() {
        for flag in FeatureFlag.allCases {
            applyChange(flag, enabled: isEnabled(flag))
        }
        debug("已开启的功能：\(self.enabledFlags)")
    }
    
    func isEnabled(_ flag: FeatureFlag) -> Bool {
        return enabledFlags.contains(flag)
    }
    
    func enable(_ flag: FeatureFlag) {
        setEnabled(flag, enabled: true)
    }
    
    func disable(_ flag: FeatureFlag) {
        setEnabled(flag, enabled: false)
    }
    
    func setEnabled(_ flag: FeatureFlag, enabled: Bool) {
        if enabled {
            enabledFlags.insert(flag)
        } else {
            enabledFlags.remove(flag)
        }
        log("\(flag) 已被\(enabled ? "开启" : "关闭")")
        applyChange(flag, enabled: enabled)
    }
    
    /// 功能开关的作用点：每个 case 都要真的改变某个行为或界面，
    /// 否则该开关就只是「隐藏入口」，关掉之后功能依然可用。
    private func applyChange(_ flag: FeatureFlag, enabled: Bool) {
        switch flag {
        case .deduplicateLibraries:
            ClientManifest.deduplicateLibraries = enabled
        case .multiplayer:
            // 联机页的门禁由 AppRouter.isRouteAvailable(_:) 读取开关状态；
            // 这里在开关变化时立刻把停在联机页的会话退出去。
            // AppRouter 属于主线程隔离，切开关可能来自任意线程，因此显式跳一次。
            Task { @MainActor in
                AppRouter.shared.enforceFlagGates()
            }
        }
    }
}

enum FeatureFlag: String, Codable, CaseIterable {
    case deduplicateLibraries
    case multiplayer
}
