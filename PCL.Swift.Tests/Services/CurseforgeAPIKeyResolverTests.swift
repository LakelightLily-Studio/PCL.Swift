//
//  CurseforgeAPIKeyResolverTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// Key 的层级解析：手填优先、空白一律当没填。
struct CurseforgeAPIKeyResolverTests {
    @Test func userProvidedWinsOverBundled() {
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: "user-key", bundled: "bundled-key") == "user-key")
    }

    @Test func fallsBackToBundledKey() {
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: nil, bundled: "bundled-key") == "bundled-key")
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: "", bundled: "bundled-key") == "bundled-key")
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: "   ", bundled: "bundled-key") == "bundled-key")
    }

    @Test func returnsNilWhenNothingIsUsable() {
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: nil, bundled: nil) == nil)
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: "", bundled: "") == nil)
        #expect(CurseforgeAPIKeyResolver.resolve(userProvided: "\n", bundled: "\t") == nil)
    }

    @Test func stripsSurroundingQuotes() {
        // 从网页或聊天记录里复制 Key 时常带着引号，带引号的 Key 一定被服务端拒绝。
        #expect(CurseforgeAPIKeyResolver.normalized("\"abc\"") == "abc")
        #expect(CurseforgeAPIKeyResolver.normalized(" 'abc' ") == "abc")
        #expect(CurseforgeAPIKeyResolver.normalized("\"\"") == nil)
    }

    @Test func trimsWhitespace() {
        #expect(CurseforgeAPIKeyResolver.normalized("  key  \n") == "key")
    }
}
