//
//  MinecraftVersionOrderTests.swift
//  PCL.Mac.Tests
//

import Foundation
import Testing
import Core

/// `MinecraftVersion` 的排序规则此前只能通过全局清单间接验证。
/// 规则本身是纯函数，这里脱离启动流程直接覆盖两条分支。
struct MinecraftVersionOrderTests {
    /// 没有清单时按版本号自然序比较。
    @Test func fallsBackToNumericStringOrderWithoutManifest() {
        #expect(MinecraftVersion.isOrdered(.init("1.21.10"), before: .init("1.21.11-pre2"), using: nil))
        #expect(MinecraftVersion.isOrdered(.init("1.20.6"), before: .init("1.21"), using: nil))
        #expect(!MinecraftVersion.isOrdered(.init("1.21.10"), before: .init("1.21.10"), using: nil))
    }

    /// 自然序要点：比较的是版本号里的数字段，不是逐字符。
    @Test func numericComparisonOrdersSnapshotsAfterTheirRelease() {
        #expect(MinecraftVersion.isOrdered(.init("1.21.9"), before: .init("1.21.10"), using: nil))
        #expect(!MinecraftVersion.isOrdered(.init("1.21.10"), before: .init("1.21.9"), using: nil))
    }

    /// 清单里能查到发布时间时，按发布时间排序（覆盖字符串比较会给出相反答案的情况）。
    @Test func prefersReleaseTimeWhenManifestKnowsBothVersions() async throws {
        let json = """
        {
          "latest": { "release": "zzz-old", "snapshot": "zzz-old" },
          "versions": [
            { "id": "zzz-old", "type": "release", "url": "https://example.invalid/1", "time": "2020-01-01T00:00:00+00:00", "releaseTime": "2020-01-01T00:00:00+00:00" },
            { "id": "aaa-new", "type": "release", "url": "https://example.invalid/2", "time": "2025-01-01T00:00:00+00:00", "releaseTime": "2025-01-01T00:00:00+00:00" }
          ]
        }
        """
        let manifest: VersionManifest = try JSONDecoder.shared.decode(VersionManifest.self, from: Data(json.utf8))
        // 字符串比较会说 "aaa-new" < "zzz-old"，清单里的发布时间正好相反。
        #expect(MinecraftVersion.isOrdered(.init("zzz-old"), before: .init("aaa-new"), using: manifest))
        #expect(!MinecraftVersion.isOrdered(.init("aaa-new"), before: .init("zzz-old"), using: manifest))
    }

    /// 只有一个版本能查到时间时整体退化为字符串比较，而不是半用时间半用字符串。
    @Test func fallsBackWhenOnlyOneVersionIsInTheManifest() async throws {
        let json = """
        {
          "latest": { "release": "zzz-old", "snapshot": "zzz-old" },
          "versions": [
            { "id": "zzz-old", "type": "release", "url": "https://example.invalid/1", "time": "2020-01-01T00:00:00+00:00", "releaseTime": "2020-01-01T00:00:00+00:00" }
          ]
        }
        """
        let manifest: VersionManifest = try JSONDecoder.shared.decode(VersionManifest.self, from: Data(json.utf8))
        #expect(!MinecraftVersion.isOrdered(.init("zzz-old"), before: .init("aaa-new"), using: manifest))
    }
}
