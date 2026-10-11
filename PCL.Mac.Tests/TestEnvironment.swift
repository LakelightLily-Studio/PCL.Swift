//
//  TestEnvironment.swift
//  PCL.Mac.Tests
//

import Foundation
import Testing

/// 测试环境的统一开关。
///
/// 一部分测试要访问 Mojang / Modrinth 的线上接口，在 CI 里既慢又不稳定，
/// 因此默认跳过；需要跑完整套时设置 `PCL_MAC_NETWORK_TESTS=1`。
enum TestEnvironment {
    /// 是否允许发起真实网络请求。
    static let networkTestsEnabled: Bool = {
        ProcessInfo.processInfo.environment["PCL_MAC_NETWORK_TESTS"] == "1"
    }()

    /// 用于 `@Test(.enabled(if:))`：非联网环境下跳过依赖网络的测试。
    static var networkAvailable: Bool { networkTestsEnabled }
}
