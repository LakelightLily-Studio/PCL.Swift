//
//  UpdateManifestTests.swift
//  PCL.Swift.Tests
//
//  清单是新的单点：解错一个字段，全量用户都会「永远是最新版本」，
//  所以这里把默认值、架构映射、多源顺序都钉住。
//

import Testing
import Foundation
@testable import Core

@Suite("更新清单")
struct UpdateManifestTests {
    private func decode(_ json: String) throws -> UpdateManifest {
        try JSONDecoder.shared.decode(UpdateManifest.self, from: Data(json.utf8))
    }

    @Test("最小清单：缺省字段按默认值补")
    func minimalManifest() throws {
        let manifest = try decode("""
        {"schema": 1, "releases": [{"version": "2.1.0", "assets": {"arm64": {"url": "https://example.com/a.zip"}}}]}
        """)
        #expect(manifest.channel == "stable")
        let release = try #require(manifest.releases.first)
        #expect(release.prerelease == false)
        #expect(release.yanked == false)
        #expect(release.rollout == 100)
        #expect(release.assets["arm64"]?.mirrors.isEmpty == true)
        #expect(release.assets["arm64"]?.sha256 == nil)
    }

    @Test("按架构挑包：x64 不会拿到 arm64 的包")
    func assetSelection() throws {
        let manifest = try decode("""
        {"releases": [{"version": "2.1.0", "assets": {
            "arm64": {"url": "https://example.com/arm64.zip"},
            "x86_64": {"url": "https://example.com/x64.zip"}}}]}
        """)
        let release = try #require(manifest.releases.first)
        #expect(release.asset(for: .arm64)?.url.absoluteString.hasSuffix("arm64.zip") == true)
        #expect(release.asset(for: .x64)?.url.absoluteString.hasSuffix("x64.zip") == true)
        #expect(release.asset(for: .fatFile)?.url.absoluteString.hasSuffix("arm64.zip") == true)
        #expect(release.asset(for: .unknown) == nil)
    }

    @Test("主地址在前、备用地址去重")
    func allURLs() throws {
        let manifest = try decode("""
        {"releases": [{"version": "2.1.0", "assets": {"arm64": {
            "url": "https://a.example.com/x.zip",
            "mirrors": ["https://b.example.com/x.zip", "https://a.example.com/x.zip"]}}}]}
        """)
        let asset = try #require(manifest.releases.first?.assets["arm64"])
        #expect(asset.allURLs.map(\.absoluteString) == [
            "https://a.example.com/x.zip",
            "https://b.example.com/x.zip",
        ])
    }

    @Test("撤包与预发布由调用方过滤，DTO 只如实解码")
    func flags() throws {
        let manifest = try decode("""
        {"releases": [
            {"version": "2.2.0", "prerelease": true, "assets": {}},
            {"version": "2.1.0", "yanked": true, "assets": {}},
            {"version": "2.0.9", "rollout": 5, "notes_url": "https://example.com/notes", "assets": {}}
        ]}
        """)
        #expect(manifest.releases[0].prerelease)
        #expect(manifest.releases[1].yanked)
        #expect(manifest.releases[2].rollout == 5)
        #expect(manifest.releases[2].notesURL?.absoluteString == "https://example.com/notes")
    }
}
