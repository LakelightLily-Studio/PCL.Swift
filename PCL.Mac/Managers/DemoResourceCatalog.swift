//
//  DemoResourceCatalog.swift
//  PCL.Mac
//
//  demo 分支专用：资源列表改为读取打包进 App 的静态数据，不再请求 Modrinth。
//  数据由 api.modrinth.com/v2/search 按下载量取前 12 项导出，图标一并下载到
//  Resources/demo/ 下。合回 main 之前应当整体删除。
//

import Foundation
import Core

/// 演示用的本地资源目录。
final class DemoResourceCatalog {
    static let shared: DemoResourceCatalog = .init()

    private let projectsByType: [ResourceType: [ModrinthProject]]
    private let loadError: Error?

    private init() {
        do {
            let url = URLConstants.resourcesURL.appending(path: "demo-resources.json")
            let data = try Data(contentsOf: url)
            let projects = try Self.decode(data)
            self.projectsByType = projects
            self.loadError = nil
            log("已载入演示资源目录：\(projects.mapValues(\.count))")
        } catch {
            self.projectsByType = [:]
            self.loadError = error
            err("载入演示资源目录失败：\(error.localizedDescription)")
        }
    }

    /// 把 JSON 里的图标文件名替换成打包后的绝对 file URL，再交给 Decodable。
    ///
    /// 之所以不在 JSON 里直接写绝对路径：App 的 Resources 目录在构建产物里，
    /// 路径只有在运行时才知道。
    private static func decode(_ data: Data) throws -> [ResourceType: [ModrinthProject]] {
        guard var raw = try JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else {
            throw SimpleError("演示资源目录格式错误。")
        }
        for (type, items) in raw {
            raw[type] = items.map { item in
                var item = item
                if let name = item["icon_url"] as? String {
                    let iconURL = URLConstants.resourcesURL.appending(path: name)
                    item["icon_url"] = iconURL.absoluteString
                }
                return item
            }
        }

        let patched = try JSONSerialization.data(withJSONObject: raw)
        let decoded = try JSONDecoder().decode([String: [ModrinthProject]].self, from: patched)

        var mapped: [ResourceType: [ModrinthProject]] = [:]
        for (key, projects) in decoded {
            guard let type = ResourceType(rawValue: key) else {
                warn("演示资源目录中出现未知类型 \(key)，已跳过")
                continue
            }
            mapped[type] = projects
        }
        return mapped
    }

    /// 与 `ModrinthAPIClient.search` 相同形状的本地实现。
    ///
    /// 保留分页语义：每页 40 条，`totalHits` 取本地数据的总数，这样
    /// `ResourcesSearchPage` 的分页控件不用改。查询词按标题与描述做本地过滤。
    func search(type: ResourceType, _ query: String?, pageIndex: Int = 0) async throws -> ModrinthAPIClient.SearchResponse {
        if let loadError { throw loadError }

        let all = projectsByType[type] ?? []
        let keyword = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched: [ModrinthProject]
        if keyword.isEmpty {
            matched = all
        } else {
            matched = all.filter {
                $0.title.lowercased().contains(keyword) || $0.description.lowercased().contains(keyword)
            }
        }

        let limit = 40
        let offset = pageIndex * limit
        let page = matched.dropFirst(offset).prefix(limit)
        return .init(hits: Array(page), offset: offset, limit: limit, totalHits: matched.count)
    }
}
