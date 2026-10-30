//
//  ChangelogLoader.swift
//  PCL.Swift
//
//  主页预设「PCL.Swift 更新日志」的取内容逻辑。
//
//  三个来源，优先级从高到低：
//  1. 国内分发仓库的 changelog.md（publish-dist.sh 每次发版从仓库根目录同步过去）——
//     改日志不用发版，也不受 GitHub 访问速度影响；
//  2. 上一次成功拉取的缓存（Caches/Changelog/changelog.md），断网时继续用；
//  3. 打包进 App 的 Resources/CHANGELOG.md，首次启动或从来没联网过时的兜底。
//
//  与 HomepageLoader 分开：那份是给自定义主页（XAML）用的，这里的格式是 Markdown。
//

import Foundation
import Core

enum ChangelogLoader {
    /// 国内分发仓库里的文件名。
    static let remotePath: String = "changelog.md"

    /// 打包进 App 的那份（构建时由 CI 从仓库根目录的 CHANGELOG.md 复制过来）。
    static var bundledURL: URL {
        URLConstants.resourcesURL.appending(path: "CHANGELOG.md")
    }

    private static var cacheDirectory: URL {
        URLConstants.cacheURL.appending(path: "Changelog")
    }

    private static var cacheFileURL: URL {
        cacheDirectory.appending(path: "changelog.md")
    }

    static func loadBundled() -> ChangelogDocument? {
        load(from: bundledURL, description: "内置更新日志")
    }

    static func loadCached() -> ChangelogDocument? {
        load(from: cacheFileURL, description: "缓存的更新日志")
    }

    /// 依次尝试国内入口。全部失败时抛出最后一个错误，由调用方决定是否退回缓存。
    static func loadRemote() async throws -> ChangelogDocument {
        var lastError: Error?
        for url in DomesticAssets.mirrors(for: remotePath) {
            do {
                let response = try await HTTPClient.shared.get(
                    url,
                    headers: ["Accept": "text/plain, text/markdown, */*"],
                    revalidate: true,
                    timeout: 15
                )
                guard (200..<300).contains(response.statusCode) else {
                    throw SimpleError("返回 \(response.statusCode)")
                }
                guard let content = String(data: response.data, encoding: .utf8) else {
                    throw SimpleError("内容不是 UTF-8 文本")
                }
                let document: ChangelogDocument = ChangelogParser.parse(content)
                guard !document.entries.isEmpty else {
                    throw SimpleError("更新日志里没有任何版本条目")
                }
                saveCache(response.data)
                return document
            } catch let error where error.isCancellationError {
                throw error
            } catch {
                lastError = error
                warn("更新日志入口失败 \(url.host ?? "?")：\(error.localizedDescription)")
            }
        }
        throw lastError ?? SimpleError("没有可用的更新日志入口。")
    }

    private static func load(from url: URL, description: String) -> ChangelogDocument? {
        do {
            let content: String = try String(contentsOf: url, encoding: .utf8)
            let document: ChangelogDocument = ChangelogParser.parse(content)
            return document.entries.isEmpty ? nil : document
        } catch {
            // 没有这份文件是正常情况（首次启动 / 从没联网），不刷错误日志。
            debug("读取\(description)失败：\(error.localizedDescription)")
            return nil
        }
    }

    private static func saveCache(_ data: Data) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            warn("写入更新日志缓存失败：\(error.localizedDescription)")
        }
    }
}
