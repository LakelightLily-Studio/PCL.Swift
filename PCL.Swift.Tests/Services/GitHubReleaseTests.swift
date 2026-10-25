//
//  GitHubReleaseTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 更新渠道的 JSON 映射一旦写错，用户端只会看到「永远是最新版本」——静默且难查，
/// 所以这里对着真实 API 解一次（默认跳过，设 PCL_MAC_NETWORK_TESTS=1 才跑）。
struct GitHubReleaseTests {
    @Test(.enabled(if: TestEnvironment.networkAvailable))
    func decodesPublishedRelease() async throws {
        let url: URL = URL(string: "https://api.github.com/repos/functy23/PCL.Swift/releases?per_page=5")!
        let releases: [GitHubRelease] = try await HTTPClient.shared.get(
            url,
            headers: ["Accept": "application/vnd.github+json"],
            throwOnError: true,
            revalidate: true
        ).decode([GitHubRelease].self)

        let published: [GitHubRelease] = releases.filter { !$0.draft }
        #expect(!published.isEmpty)
        #expect(published.allSatisfy { LauncherVersion.components(of: $0.tagName) != nil })

        // 至少有一个已发布版本带着能直接替换 App Bundle 的 zip 包。
        let hasUpdatePackage: Bool = published.contains { release in
            release.assets.contains { asset in
                asset.name.hasPrefix("PCL.Swift-") && asset.name.hasSuffix(".zip") && asset.size > 0
            }
        }
        #expect(hasUpdatePackage)

        // 资产的下载地址必须真的是 releases/download 路径，否则更新器会拿 404。
        let downloadURLs: [URL] = published.flatMap { $0.assets.map(\.downloadURL) }
        #expect(downloadURLs.allSatisfy { $0.path.contains("/releases/download/") })
    }
}
