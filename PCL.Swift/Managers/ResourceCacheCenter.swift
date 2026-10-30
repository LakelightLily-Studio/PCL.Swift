//
//  ResourceCacheCenter.swift
//  PCL.Swift
//
//  社区资源的缓存中心（设置 → 其他 → 缓存）。
//
//  两类缓存，规则不同：
//  - **资源列表**（搜索结果 / 已安装模组列表）：只在内存里，按「时间限制」过期（10 / 30 分钟）。
//  - **图标**：开启后落盘到缓存目录，关掉就完全不走缓存。
//
//  搜索结果不落盘：换源或换筛选后，磁盘缓存很容易给出过期数据。
//

import SwiftUI
import Core

@MainActor
final class ResourceCacheCenter {
    static let shared: ResourceCacheCenter = .init()

    /// 一页搜索结果。
    struct Page {
        let results: [ProjectListItemModel]
        let totalPages: Int
        let curseforgeSkipped: Bool
    }

    private struct Entry<Value> {
        let value: Value
        let date: Date
    }

    private var pages: [String: Entry<Page>] = [:]
    private var installed: [String: Entry<[(URL, Resource)]>] = [:]
    /// 图标的内存层：避免每帧都去读盘解码。落盘的那份才是跨会话的缓存。
    private var images: [String: NSImage] = [:]

    /// 图标落盘的位置。
    static var imageDirectory: URL { URLConstants.cacheURL.appending(path: "images") }

    private init() {}

    // MARK: - 开关

    var isListCacheEnabled: Bool { LauncherConfig.shared.enableResourceListCache }
    var isImageCacheEnabled: Bool { LauncherConfig.shared.enableImageCache }

    /// 资源列表的存活时间（10 / 30 分钟，由设置决定）。
    private var listTTL: TimeInterval {
        TimeInterval(max(LauncherConfig.shared.resourceListCacheMinutes, 1)) * 60
    }

    // MARK: - 资源列表

    func page(for key: String) -> Page? {
        guard isListCacheEnabled else { return nil }
        return validEntry(pages[key])?.value
    }

    func store(_ page: Page, for key: String) {
        guard isListCacheEnabled else { return }
        pages[key] = .init(value: page, date: Date())
    }

    func installedList(for key: String) -> [(URL, Resource)]? {
        guard isListCacheEnabled else { return nil }
        return validEntry(installed[key])?.value
    }

    func storeInstalled(_ list: [(URL, Resource)], for key: String) {
        guard isListCacheEnabled else { return }
        installed[key] = .init(value: list, date: Date())
    }

    private func validEntry<Value>(_ entry: Entry<Value>?) -> Entry<Value>? {
        guard let entry else { return nil }
        guard Date().timeIntervalSince(entry.date) < listTTL else { return nil }
        return entry
    }

    // MARK: - 图标

    /// 图标缓存用的 key：URL + 裁剪区域（同一张头像的原图与裁剪图不能共用一份）。
    static func imageKey(_ url: URL, cropRect: CGRect?) -> String {
        guard let cropRect else { return url.absoluteString }
        return url.absoluteString + "#" + "\(cropRect)"
    }

    func image(for key: String) -> NSImage? {
        guard isImageCacheEnabled else { return nil }
        if let cached = images[key] { return cached }
        // 内存里没有就翻磁盘：上次会话存下来的图不用重新下载。
        let fileURL: URL = Self.imageDirectory.appending(path: key.sha1)
        guard let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) else { return nil }
        images[key] = image
        return image
    }

    func store(_ image: NSImage, for key: String) {
        guard isImageCacheEnabled else { return }
        images[key] = image

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try FileManager.default.createDirectory(at: Self.imageDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.imageDirectory.appending(path: key.sha1))
        } catch {
            // 写不进去只影响下次启动的命中率，不值得打断当前操作。
            warn("写入图标缓存失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 清理

    /// 清空列表缓存（关掉开关时调用，避免"关了还在用旧数据"）。
    func clearLists() {
        pages.removeAll()
        installed.removeAll()
    }

    /// 清空图标缓存：内存与磁盘一起删（关了就没缓存）。
    func clearImages() {
        images.removeAll()
        do {
            try FileManager.default.removeItem(at: Self.imageDirectory)
        } catch CocoaError.fileNoSuchFile {
            // 本来就没有缓存目录，正常。
        } catch {
            warn("清空图标缓存失败：\(error.localizedDescription)")
        }
    }
}
