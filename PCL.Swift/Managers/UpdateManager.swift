//
//  UpdateManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/26.
//

import Foundation
import AppKit
import Core
import ZIPFoundation

/// 启动器更新检查与安装。
///
/// 更新渠道是本源仓库的 GitHub Release。以前读的是 Cylorine Studio 的 update.json，
/// 那份元数据不跟随本仓库发版，检查更新实际上永远拿不到新版本。
class UpdateManager {
    public static let shared: UpdateManager = .init()

    /// 更新来源仓库。
    fileprivate static let repository: String = "functy23/PCL.Swift"
    /// 一次取多少条 Release。20 条足够覆盖落后很多个版本的用户。
    private static let releasesPerPage: Int = 20

    private var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=\(Self.releasesPerPage)")!
    }

    private init() {}

    /// 检查是否有比当前更新的稳定版。
    /// - Returns: 有更新时返回目标版本信息，否则返回 nil。
    public func checkUpdates() async throws -> UpdateInfo? {
        // 本地开发构建（CFBundleVersion 为 0）与 Debug 构建不提示更新：
        // 它们本来就领先于最新发布版，提示只会干扰调试。
        if Metadata.debugMode || Metadata.bundleVersion == 0 { return nil }

        let releases: [GitHubRelease] = try await HTTPClient.shared.get(
            releasesURL,
            headers: ["Accept": "application/vnd.github+json"],
            throwOnError: true,
            revalidate: true
        ).decode([GitHubRelease].self)

        // 只看稳定版：草稿与预发布不该推给普通用户。
        let candidates: [GitHubRelease] = releases
            .filter { !$0.draft && !$0.prerelease && LauncherVersion.components(of: $0.tagName) != nil }
            // Array 不满足 Comparable，直接用版本比较排序（降序）。
            .sorted { LauncherVersion.isNewer($0.tagName, than: $1.tagName) }

        for release in candidates where LauncherVersion.isNewer(release.tagName, than: Metadata.appVersion) {
            // 某个版本没带可用的 zip 时跳过它，继续看下一个更旧的版本，
            // 而不是把用户卡在一个装不上的版本上。
            if let info: UpdateInfo = release.updateInfo(for: .systemArchitecture()) {
                return info
            }
        }
        return nil
    }

    /// 下载并安装更新，完成后重启。
    public func installUpdate(_ version: UpdateInfo) async throws {
        let destination: URL = URLConstants.tempURL.appending(path: "launcher-update-\(version.version)")
        let downloadItem: DownloadItem = .init(
            url: version.downloads.url,
            destination: destination,
            sha1: version.downloads.sha1
        )
        defer { try? FileManager.default.removeItem(at: destination) }
        try await FileDownloader.shared.download(downloadItem)
        try FileManager.default.unzipItem(at: destination, to: destination.deletingLastPathComponent())

        // 更新包里是 PCL.Swift.app；早期构建的包叫 PCL.Mac.app，一并兼容，
        // 否则从 1.x 升上来的用户会停在「更新包格式错误」。
        let bundleNames: [String] = ["PCL.Swift.app", "PCL.Mac.app"]
        guard let newBundle: URL = bundleNames
            .map({ URLConstants.tempURL.appending(path: $0) })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw SimpleError("更新包格式错误，请到 GitHub Release 页面手动下载安装。")
        }
        _ = try FileManager.default.replaceItemAt(
            Bundle.main.bundleURL,
            withItemAt: newBundle,
            backupItemName: "PCL.Swift.app.backup",
            options: [.usingNewMetadataOnly]
        )

        log("App Bundle 替换完成，正在重启")
        // 使用 /usr/bin/open 延迟开启新进程，确保同时只有一个进程存在。
        let process: Process = .init()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        try process.run()
        await NSApplication.shared.terminate(nil)
    }
}

// MARK: - GitHub Release → UpdateInfo

/// 把 GitHub Release 映射成启动器更新器要的形状。
///
/// DTO 本身在 Core 的 GitHubRelease（那边可测解码）；这里只放本启动器的取舍：
/// 用哪个资产当更新包、摘要怎么写。
private extension GitHubRelease {
    /// 更新包：发布页里还有 dmg 与 build.xcarchive.zip，只有 PCL.Swift-<版本>.zip
    /// 是能直接替换 App Bundle 的那种，所以按前缀 + 后缀筛，不按顺序猜。
    /// - Parameter architecture: 当前运行的架构。更新包从 2.0.4 起按架构分开，
    ///   挑包逻辑在 Core 的 GitHubRelease.updateArchive(for:)，这里只做映射。
    func updateInfo(for architecture: Architecture) -> UpdateInfo? {
        guard let asset: Asset = updateArchive(for: architecture) else { return nil }

        let trimmedName: String = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(
            name: trimmedName.isEmpty ? versionString : trimmedName,
            version: versionString,
            summary: summary,
            updateLogLinks: [.init(name: "查看完整更新日志", url: htmlURL)],
            downloads: .init(url: asset.downloadURL, size: asset.size, sha1: nil)
        )
    }

    /// 弹窗只显示一行摘要：取正文第一段有效文本，去掉 Markdown 标记并截断。
    var summary: String {
        let lines: [String] = (body ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        var line: String = lines.first ?? "打开 Release 页面查看本次更新内容。"
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("> ") {
            line.removeFirst(2)
        }
        line = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
        return line.count > 120 ? String(line.prefix(120)) + "……" : line
    }
}
