//
//  GitHubRelease.swift
//  PCL.Swift.Core
//

import Foundation

/// GitHub Release 里本项目用得到的字段。
///
/// 只声明用得到的字段：GitHub 的响应很大，多解一个字段就是多一条可能失败的约束。
/// 放在 Core 里是为了让解码本身可测——更新渠道的映射一旦写错，
/// 用户端的表现是「永远显示已是最新版本」，静默且难查。
public struct GitHubRelease: Decodable {
    public struct Asset: Decodable {
        public let name: String
        public let size: Int
        public let downloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name, size
            case downloadURL = "browser_download_url"
        }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name, body, draft, prerelease, assets
    }

    /// 去掉 v 前缀的版本号，例如 v2.0.1 → 2.0.1。
    public var versionString: String {
        var text: String = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        return text
    }
}
