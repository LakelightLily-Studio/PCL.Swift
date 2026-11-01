//
//  DomesticAssets.swift
//  PCL.Swift.Core
//
//  国内分发仓库（GitCode）里的静态资源地址。
//
//  图片、更新日志这类"换一份不用发版"的资源放在 functy/pcl-swift-dist 仓库里：
//  换头像、改日志只要往那边推一次，客户端下一次刷新就能拿到。
//
//  同一份资源给三条取法，顺序是 API raw → raw.gitcode.com → Gitee：
//  仓库公开审核期间 raw.gitcode.com 会回 403「暂不支持预览」，API raw 一直可读，
//  所以它排第一；三条都失败时调用方用自己的兜底（打包在 App 里的图 / 内置日志）。
//

import Foundation

public enum DomesticAssets {
    /// 国内分发仓库的 raw 直链根（公开后可用）。
    public static let rawBase: URL = URL(string: "https://raw.gitcode.com/functy/pcl-swift-dist/raw/main/")!
    /// GitCode 的 API raw：审核期间唯一稳定可读的入口。
    public static let apiBase: URL = URL(string: "https://api.gitcode.com/api/v5/repos/functy/pcl-swift-dist/raw/")!
    /// Gitee 镜像仓库。
    public static let giteeBase: URL = URL(string: "https://gitee.com/functy/pcl-swift-dist/raw/main/")!

    /// 仓库内相对路径 → 依次尝试的绝对地址。
    /// - Parameters:
    ///   - path: 相对仓库根目录的路径，例如 `assets/about/Functy.png`。
    ///   - cacheBust: 可选的版本号。会作为查询参数拼到每条地址上，
    ///     让「换了图但路径没变」的资源能绕开客户端磁盘缓存（见 InstanceIconStore.iconSetVersion）。
    public static func mirrors(for path: String, cacheBust: String? = nil) -> [URL] {
        let relative: String = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return [
            apiURL(relative, cacheBust: cacheBust),
            withCacheBust(rawBase.appending(path: relative), cacheBust),
            withCacheBust(giteeBase.appending(path: relative), cacheBust),
        ]
    }

    /// 给地址补一个 `v=` 参数；没有版本号就原样返回。
    private static func withCacheBust(_ url: URL, _ cacheBust: String?) -> URL {
        guard let cacheBust, !cacheBust.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items: [URLQueryItem] = components.queryItems ?? []
        items.append(URLQueryItem(name: "v", value: cacheBust))
        components.queryItems = items
        return components.url ?? url
    }

    /// 仓库里放「更多」页头像的目录。
    public static let aboutDirectory: String = "assets/about"

    /// 某个头像在仓库里的相对路径。文件名就是 Assets.xcassets 里 imageset 的名字。
    public static func aboutImagePath(_ name: String) -> String {
        aboutDirectory + "/" + name + ".png"
    }

    /// 仓库里放「实例图标」的目录。
    ///
    /// 这套图标（草方块、工作台、钻石剑……）同样不跟着发版走：换一张图只要往国内仓库推一次。
    /// 文件名是图标的 id（见 InstanceIconCatalog），打包在 App 里的同图只作离线兜底。
    public static let instanceIconDirectory: String = "assets/icons"

    /// 某个实例图标在仓库里的相对路径。
    public static func instanceIconPath(_ name: String) -> String {
        instanceIconDirectory + "/" + name + ".png"
    }

    /// API raw 需要 `?ref=main` 才会给内容（不带时可能落到默认分支的裸文件接口）。
    private static func apiURL(_ path: String, cacheBust: String? = nil) -> URL {
        let url: URL = apiBase.appending(path: path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items: [URLQueryItem] = [URLQueryItem(name: "ref", value: "main")]
        if let cacheBust, !cacheBust.isEmpty {
            items.append(URLQueryItem(name: "v", value: cacheBust))
        }
        components.queryItems = items
        return components.url ?? url
    }
}
