//
//  FlagsManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/14.
//

import Foundation
import Core

class FlagsManager: ObservableObject {
    public static var shared: FlagsManager!
    @Published private(set) var enabledFlags: Set<FeatureFlag>
    private let defaultFlags = Set<FeatureFlag>(arrayLiteral: .deduplicateLibraries)
    
    init(enabledFlags: Set<FeatureFlag>?) {
        if let enabledFlags {
            self.enabledFlags = enabledFlags
        } else {
            self.enabledFlags = defaultFlags
        }
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
            AppRouter.shared.enforceFlagGates()
        }
    }
}

enum FeatureFlag: String, Codable, CaseIterable {
    case deduplicateLibraries
    case multiplayer
}
