//
//  MinecraftNewsService.swift
//  PCL.Swift
//
//  启动器主页用的 Minecraft 新闻。
//
//  数据源与官方启动器同一个：launchercontent.mojang.com 的 v2/news.json。
//  只取前几条做展示，点条目用系统浏览器打开原文。
//

import Foundation
import Core

struct MinecraftNewsItem: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let date: String
    let imageURL: URL?
    let link: URL?
}

enum MinecraftNewsService {
    private static let feedURL: URL = URL(string: "https://launchercontent.mojang.com/v2/news.json")!
    private static let imageBase: String = "https://launchercontent.mojang.com"

    private struct Feed: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        struct NewsImage: Decodable {
            let url: String
        }

        let id: String
        let title: String
        let category: String
        let date: String
        let readMoreLink: String?
        let newsPageImage: NewsImage?
    }

    /// 拉取新闻（最多 limit 条）。
    static func fetch(limit: Int = 3) async throws -> [MinecraftNewsItem] {
        let data: Data = try await HTTPClient.shared.get(feedURL).data
        let feed: Feed = try JSONDecoder().decode(Feed.self, from: data)
        return feed.entries.prefix(limit).map { entry in
            MinecraftNewsItem(
                id: entry.id,
                title: entry.title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: entry.category,
                date: entry.date,
                imageURL: entry.newsPageImage.flatMap { URL(string: imageBase + $0.url) },
                link: entry.readMoreLink.flatMap(URL.init(string:))
            )
        }
    }
}
