//
//  LauncherVersionTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 更新渠道换成 GitHub Release 后，版本号来自 tag，比较逻辑必须扛得住各种写法。
struct LauncherVersionTests {
    @Test func parsesCommonTagShapes() {
        #expect(LauncherVersion.components(of: "v2.0.1") == [2, 0, 1])
        #expect(LauncherVersion.components(of: "2.0") == [2, 0, 0])
        #expect(LauncherVersion.components(of: " V2 ") == [2, 0, 0])
        #expect(LauncherVersion.components(of: "2.0.1-beta.2") == [2, 0, 1])
    }

    @Test func rejectsNonVersionTags() {
        #expect(LauncherVersion.components(of: "nightly") == nil)
        #expect(LauncherVersion.components(of: "1rc") == nil)
        #expect(LauncherVersion.components(of: "") == nil)
    }

    @Test func comparesNumericallyNotLexically() {
        #expect(LauncherVersion.isNewer("2.0.10", than: "2.0.9"))
        #expect(LauncherVersion.isNewer("2.1", than: "2.0.99"))
        #expect(!LauncherVersion.isNewer("2.0", than: "2.0.0"))
        #expect(!LauncherVersion.isNewer("1.9.9", than: "2.0"))
    }

    @Test func refusesToCompareUnparseableTags() {
        #expect(!LauncherVersion.isNewer("nightly", than: "2.0"))
        #expect(!LauncherVersion.isNewer("2.0", than: "nightly"))
    }
}
