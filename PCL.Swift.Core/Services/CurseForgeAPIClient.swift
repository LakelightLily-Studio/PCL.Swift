//
//  CurseForgeAPIClient.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation
import SwiftyJSON

public class CurseForgeAPIClient {
    private let semaphore: AsyncSemaphore = .init(value: 8)
    private let apiRoot: URL
    private let apiKey: String
    
    /// CurseForge 的 Minecraft 游戏 id。
    public static let minecraftGameId: Int = 432
    
    public init(apiRoot: URL = .init(string: "https://api.curseforge.com")!, apiKey: String) {
        self.apiRoot = apiRoot
        self.apiKey = apiKey
    }
    
    public func mod(id modId: Int) async throws -> CurseForgeMod? {
        let response = try await request("/v1/mods/\(modId)")
        if response.statusCode == 404 { return nil }
        return try response.decode(Response<CurseForgeMod>.self).data
    }
    
    public func modFile(modId: Int, fileId: Int) async throws -> CurseForgeModFile? {
        let response = try await request("/v1/mods/\(modId)/files/\(fileId)")
        if response.statusCode == 404 { return nil }
        return try response.decode(Response<CurseForgeModFile>.self).data
    }
    
    /// 搜索项目。
    /// - Parameters:
    ///   - classId: 项目类型（见 `CurseForgeMod.classId(for:)`）。
    ///   - query: 搜索关键词。
    ///   - gameVersion: 过滤游戏版本。
    ///   - loader: 过滤 Mod 加载器。
    ///   - categoryId: 过滤分类。
    ///   - index: 起始下标（不是页码）。
    ///   - pageSize: 每页数量。
    public func search(
        classId: Int,
        query: String?,
        gameVersion: String? = nil,
        loader: ModLoader? = nil,
        categoryId: Int? = nil,
        index: Int = 0,
        pageSize: Int = 40
    ) async throws -> PagedResult<CurseForgeMod> {
        var params: [String: String?] = [
            "gameId": String(Self.minecraftGameId),
            "classId": String(classId),
            "index": String(index),
            "pageSize": String(pageSize),
            // 按热度排序，与 Modrinth 默认的 relevance 观感接近。
            "sortField": "2",
            "sortOrder": "desc"
        ]
        if let query, !query.isEmpty {
            params["searchFilter"] = query
        }
        if let gameVersion {
            params["gameVersion"] = gameVersion
        }
        if let loader {
            params["modLoaderType"] = String(loader.curseforgeType)
        }
        if let categoryId {
            params["categoryId"] = String(categoryId)
        }
        return try await request("/v1/mods/search", params: params).decode(PagedResult<CurseForgeMod>.self)
    }
    
    /// 某个项目的全部文件（按上传时间倒序）。
    public func files(
        modId: Int,
        gameVersion: String? = nil,
        loader: ModLoader? = nil,
        index: Int = 0,
        pageSize: Int = 50
    ) async throws -> PagedResult<CurseForgeModFile> {
        var params: [String: String?] = [
            "index": String(index),
            "pageSize": String(pageSize)
        ]
        if let gameVersion {
            params["gameVersion"] = gameVersion
        }
        if let loader {
            params["modLoaderType"] = String(loader.curseforgeType)
        }
        return try await request("/v1/mods/\(modId)/files", params: params).decode(PagedResult<CurseForgeModFile>.self)
    }
    
    /// 某一项目类型的全部分类。
    public func categories(classId: Int) async throws -> [CurseForgeCategory] {
        let response = try await request("/v1/categories", params: [
            "gameId": String(Self.minecraftGameId),
            "classId": String(classId)
        ])
        let all: [CurseForgeCategory] = try response.decode(Response<[CurseForgeCategory]>.self).data
        // 返回里第一个是「类目本身」（例如 Mods），它的 id 等于 classId，界面上不需要。
        return all.filter { $0.id != classId }
    }
    
    private func request(
        _ path: String,
        method: String = "GET",
        params: [String: String?] = [:],
        headers: [String: String?] = [:],
        body: [String: Any]? = nil
    ) async throws -> HTTPClient.Response {
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }
        var headers: [String: String?] = headers
        headers["x-api-key"] = apiKey
        
        var url: URL = apiRoot.appending(path: path)
        if !params.isEmpty {
            var components: URLComponents? = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = params
                .compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
                .sorted { $0.name < $1.name }
            if let built = components?.url {
                url = built
            }
        }
        
        let response = try await HTTPClient.shared.request(
            url: url,
            method: method,
            headers: headers,
            body: body,
            revalidate: true,
            timeout: 30
        )
        
        return response
    }
    
    public struct Response<Body: Codable>: Codable {
        public let data: Body
    }
    
    /// 带分页信息的响应（搜索 / 文件列表）。
    public struct PagedResult<Item: Codable>: Codable {
        public let data: [Item]
        public let pagination: Pagination
    }
    
    public struct Pagination: Codable {
        public let index: Int
        public let pageSize: Int
        public let resultCount: Int
        public let totalCount: Int
    }
}
