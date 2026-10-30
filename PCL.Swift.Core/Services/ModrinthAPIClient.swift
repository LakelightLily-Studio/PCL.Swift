//
//  ModrinthAPIClient.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/16.
//

import Foundation

public class ModrinthAPIClient {
    public static let shared: ModrinthAPIClient = .init(apiRoot: URL(string: "https://api.modrinth.com")!)
    
    private let apiRoot: URL
    
    private init(apiRoot: URL) {
        self.apiRoot = apiRoot
    }
    
    /// 搜索 Modrinth 项目。
    /// - Parameters:
    ///   - type: 项目类型（`ResourceType`）。
    ///   - query: 搜索关键词。
    ///   - gameVersion: 过滤游戏版本。
    ///   - loader: 过滤 Mod 加载器（Modrinth 把它算进 categories 标签里）。
    ///   - category: 过滤类别标签（如 optimization / technology）。
    ///   - pageIndex: 页码，从 0 开始。
    ///   - limit: 返回结果数量上限。
    /// - Returns: 包含搜索结果和分页信息的 `SearchResponse`。
    public func search(
        type: ResourceType,
        _ query: String?,
        forVersion gameVersion: String?,
        loader: ModLoader? = nil,
        category: String? = nil,
        pageIndex: Int = 0,
        limit: Int = 40
    ) async throws -> SearchResponse {
        // Modrinth 的 facets 是「外层 AND、内层 OR」：每个条件单独占一个内层数组。
        var facets: [[String]] = [["project_type:\(type)"]]
        if let gameVersion {
            facets.append(["versions:\(gameVersion)"])
        }
        if let loader {
            facets.append(["categories:\(loader.rawValue)"])
        }
        if let category {
            facets.append(["categories:\(category)"])
        }
        let facetsString: String = String(data: try JSONSerialization.data(withJSONObject: facets), encoding: .utf8)!
        
        let response = try await HTTPClient.shared.get(
            apiRoot.appending(path: "/v2/search"),
            params: [
                "query": query == "" ? nil : query,
                "facets": facetsString,
                "limit": String(describing: limit),
                "offset": String(describing: pageIndex * limit)
            ]
        )
        return try response.decode(SearchResponse.self)
    }
    
    /// 获取全部类别标签（按 project_type 区分，界面上用它填「类型」下拉框）。
    public func categories() async throws -> [Category] {
        try await HTTPClient.shared.get(apiRoot.appending(path: "/v2/tag/category")).decode([Category].self)
    }

    /// 获取指定 id 或 slug 对应的 `ModrinthProject`。
    /// - Parameters:
    ///   - slug: 指定 id 或 slug。
    ///   - revalidate: 是否验证本地缓存有效性。
    /// - Returns: 对应的 `ModrinthProject`，不存在时返回 `nil`。
    public func project(_ slug: String, revalidate: Bool = false) async throws -> ModrinthProject? {
        let response = try await HTTPClient.shared.get(apiRoot.appending(path: "/v2/project/\(slug)"), revalidate: revalidate)
        if response.statusCode == 404 { return nil }
        return try response.decode(ModrinthProject.self)
    }
    
    /// 批量获取指定 id 或 slug 对应的 `ModrinthProject`
    /// - Parameters:
    ///   - slugs: id 或 slug 列表。
    ///   - revalidate: 是否验证本地缓存有效性。
    /// - Returns: 对应的 `[ModrinthProject]`，长度可能与 `slugs` 不一致。
    public func projects(_ slugs: [String], revalidate: Bool = false) async throws -> [ModrinthProject] {
        let idsString = String(data: try JSONSerialization.data(withJSONObject: slugs), encoding: .utf8)!
        return try await HTTPClient.shared.get(
            apiRoot.appending(path: "/v2/projects"),
            params: ["ids": idsString],
            revalidate: revalidate
        ).decode([ModrinthProject].self)
    }
    
    /// 获取指定 project 的所有 `ModrinthVersion`。
    /// - Parameters:
    ///   - slug: 指定 project 的 id 或 slug。
    ///   - revalidate: 是否验证本地缓存有效性。
    /// - Returns: 该 project 的所有 `ModrinthVersion`（`[ModrinthVersion]`）。
    public func versions(ofProject slug: String, revalidate: Bool = false) async throws -> [ModrinthVersion] {
        return try await HTTPClient.shared.get(apiRoot.appending(path: "/v2/project/\(slug)/version"), revalidate: revalidate).decode([ModrinthVersion].self)
    }
    
    /// 获取指定 project 的所有 `ModrinthVersion`。
    /// - Parameters:
    ///   - slug: 指定 `ModrinthProject`。
    ///   - revalidate: 是否验证本地缓存有效性。
    /// - Returns: 该 project 的所有 `ModrinthVersion`（`[ModrinthVersion]`）。
    public func versions(ofProject project: ModrinthProject, revalidate: Bool = false) async throws -> [ModrinthVersion] {
        return try await versions(ofProject: project.slug, revalidate: revalidate)
    }
    
    /// 获取指定 id 对应的 `ModrinthVersion`。
    /// - Parameter id: 指定 version 的 id。
    /// - Returns: 对应的 `ModrinthVersion`，不存在时返回 `nil`。
    public func version(_ id: String) async throws -> ModrinthVersion? {
        let response = try await HTTPClient.shared.get(apiRoot.appending(path: "/v2/version/\(id)"))
        if response.statusCode == 404 { return nil }
        return try response.decode(ModrinthVersion.self)
    }
    
    /// 根据文件的 SHA-1 哈希值查询 `ModrinthVersion`。
    /// - Parameter hash: 文件的 SHA-1 哈希值。
    /// - Returns: 如果找到则返回对应的 `ModrinthVersion`，否则返回 `nil`。
    public func version(ofHash hash: String) async throws -> ModrinthVersion? {
        let response = try await HTTPClient.shared.get(apiRoot.appending(path: "/v2/version_file/\(hash)"))
        if response.statusCode == 404 { return nil }
        return try response.decode(ModrinthVersion.self)
    }
    
    /// 批量根据文件的 SHA-1 查询 `ModrinthVersion`。
    /// - Parameter hashes: 所有文件的 SHA-1 哈希值（`[String]`）。
    /// - Returns: 包含所有找到的 `ModrinthVersion` 的 dict。
    public func versions(ofHashes hashes: [String]) async throws -> [String: ModrinthVersion] {
        return try await HTTPClient.shared.post(
            apiRoot.appending(path: "/v2/version_files"),
            body: [
                "hashes": hashes,
                "algorithm": "sha1"
            ],
            using: .json
        ).decode([String: ModrinthVersion].self)
    }
    
    // MARK: - 数据模型

    /// 一个类别标签（`/v2/tag/category`）。
    ///
    /// `header` 是标签的分组（categories / resolutions / features…）。
    /// 加载器（forge / fabric…）**不在**这张表里，它们是搜索时单独的 categories facet，
    /// 由「Mod 加载器」那一栏负责。
    public struct Category: Decodable, Hashable, Identifiable {
        private enum CodingKeys: String, CodingKey {
            case name, projectType = "project_type", header, icon
        }

        public let name: String
        /// 用 String 而不是 ResourceType：接口还会返回 minecraft_java_server
        /// 这类本启动器没有的类型，硬解成枚举会让**整份列表**解码失败。
        public let projectType: String
        public let header: String
        public let icon: String

        public var id: String { name }
    }
    
    public struct SearchResponse: Decodable {
        private enum CodingKeys: String, CodingKey {
            case hits, offset, limit, totalHits = "total_hits"
        }
        
        public let hits: [ModrinthProject]
        public let offset: Int
        public let limit: Int
        public let totalHits: Int
    }
}
