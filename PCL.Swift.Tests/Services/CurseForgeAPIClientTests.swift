//
//  CurseForgeAPIClientTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 真实调用 CurseForge 的用例：默认跳过，跑全量时同时设
/// PCL_MAC_NETWORK_TESTS=1 与 PCLMAC_CURSE_FORGE_API_KEY 才会执行。
///
/// 它的价值在于验证「Key 真的被服务端接受」——Issue #4 里没人验证过这条链路，
/// 空 Key 的客户端只会在下载阶段报一个看不出原因的错。
struct CurseForgeAPIClientTests {
    private static var apiKey: String? {
        CurseforgeAPIKeyResolver.normalized(ProcessInfo.processInfo.environment["PCLMAC_CURSE_FORGE_API_KEY"])
    }

    @Test(.enabled(if: TestEnvironment.networkAvailable && CurseForgeAPIClientTests.apiKey != nil))
    func fetchesModWithAPIKey() async throws {
        let key: String = try #require(Self.apiKey)
        let client: CurseForgeAPIClient = .init(apiKey: key)

        // JEI：CurseForge 上最老、最稳定的项目之一，只用来验证鉴权与解码。
        let mod: CurseForgeMod? = try await client.mod(id: 238222)
        #expect(mod?.id == 238222)
        #expect(mod?.projectType == .mod)
    }
}
