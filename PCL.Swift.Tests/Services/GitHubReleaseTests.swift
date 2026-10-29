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
        let url: URL = URL(string: "https://api.github.com/repos/LakelightLily-Studio/PCL.Swift/releases?per_page=5")!
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

    // MARK: - 按架构挑更新包（2.0.4 起资产按架构分开）

    /// 一份 2.0.4 形状的 Release：两个架构各一个 zip / dmg，外加一个无关的归档。
    private static let splitAssetRelease = """
    {
      "tag_name": "v2.0.4",
      "name": "2.0.4",
      "body": "- 按架构分开构建",
      "html_url": "https://github.com/LakelightLily-Studio/PCL.Swift/releases/tag/v2.0.4",
      "draft": false,
      "prerelease": false,
      "assets": [
        {"name": "PCL.Swift-v2.0.4-x86_64.zip", "size": 2, "browser_download_url": "https://example.com/x86_64.zip"},
        {"name": "PCL.Swift-v2.0.4-arm64.zip", "size": 1, "browser_download_url": "https://example.com/arm64.zip"},
        {"name": "PCL.Swift-v2.0.4-arm64.dmg", "size": 3, "browser_download_url": "https://example.com/arm64.dmg"},
        {"name": "build.xcarchive.zip", "size": 4, "browser_download_url": "https://example.com/archive.zip"}
      ]
    }
    """

    /// 2.0.3 及更早：只有一个不带架构后缀的通用包。
    private static let legacyRelease = """
    {
      "tag_name": "v2.0.3",
      "name": "2.0.3",
      "body": "- 旧包",
      "html_url": "https://github.com/LakelightLily-Studio/PCL.Swift/releases/tag/v2.0.3",
      "draft": false,
      "prerelease": false,
      "assets": [
        {"name": "PCL.Swift-v2.0.3.zip", "size": 5, "browser_download_url": "https://example.com/legacy.zip"}
      ]
    }
    """

    @Test func picksArchiveForRunningArchitecture() throws {
        let release: GitHubRelease = try JSONDecoder().decode(GitHubRelease.self, from: Data(Self.splitAssetRelease.utf8))
        #expect(release.updateArchive(for: .arm64)?.name == "PCL.Swift-v2.0.4-arm64.zip")
        #expect(release.updateArchive(for: .x64)?.name == "PCL.Swift-v2.0.4-x86_64.zip")
        // dmg 与 build.xcarchive.zip 都不该被选中：前者不是更新包，后者不是本启动器的包。
        #expect(release.updateArchive(for: .arm64)?.name.hasSuffix(".dmg") == false)
    }

    @Test func fallsBackToLegacyUniversalArchive() throws {
        let release: GitHubRelease = try JSONDecoder().decode(GitHubRelease.self, from: Data(Self.legacyRelease.utf8))
        #expect(release.updateArchive(for: .arm64)?.name == "PCL.Swift-v2.0.3.zip")
        #expect(release.updateArchive(for: .x64)?.name == "PCL.Swift-v2.0.3.zip")
    }

    @Test func refusesArchitectureItDoesNotShip() throws {
        // 只有 arm64 包时，Intel 机器不该被提示更新（装上也跑不起来）。
        let json: String = """
        {"tag_name":"v2.0.4","name":"2.0.4","body":"- x","html_url":"https://example.com/r","draft":false,"prerelease":false,
         "assets":[{"name":"PCL.Swift-v2.0.4-arm64.zip","size":1,"browser_download_url":"https://example.com/arm64.zip"}]}
        """
        let release: GitHubRelease = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.updateArchive(for: .arm64) != nil)
        #expect(release.updateArchive(for: .x64) == nil)
    }
}