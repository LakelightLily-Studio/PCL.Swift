//
//  DemoResourceCatalogTests.swift
//  PCL.Mac.Tests
//
//  demo 分支专用：确认打包进 App 的静态资源列表能被正常解码。
//

import Foundation
import Testing
@testable import PCL_Swift
import Core

struct DemoResourceCatalogTests {
    /// ResourceType 没有实现 CaseIterable，这里显式列出。
    private static let allTypes: [ResourceType] = [.mod, .resourcepack, .shader, .modpack]

    @Test func bundledCatalogDecodes() throws {
        let url = try #require(
            Bundle.main.url(forResource: "demo-resources", withExtension: "json"),
            "演示资源目录没有被打包进 App"
        )
        let data = try Data(contentsOf: url)
        let catalog = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]],
            "演示资源目录不是预期的字典结构"
        )

        for type in Self.allTypes {
            let items = try #require(catalog[type.rawValue], "\(type.rawValue) 没有条目")
            #expect(!items.isEmpty)
        }
    }

    @Test func catalogServesEveryType() async throws {
        for type in Self.allTypes {
            let response = try await DemoResourceCatalog.shared.search(type: type, "", pageIndex: 0)
            #expect(!response.hits.isEmpty, "\(type.rawValue) 的本地列表为空")
            #expect(response.totalHits == response.hits.count)
        }
    }

    @Test func catalogFiltersByKeyword() async throws {
        let response = try await DemoResourceCatalog.shared.search(type: .mod, "fabric", pageIndex: 0)
        #expect(!response.hits.isEmpty)
        for hit in response.hits {
            let haystack = (hit.title + " " + hit.description).lowercased()
            #expect(haystack.contains("fabric"))
        }
    }
}
