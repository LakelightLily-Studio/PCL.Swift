//
//  DomesticImage.swift
//  PCL.Swift
//
//  「更多」页（关于与鸣谢）的头像：从国内分发仓库取，失败时显示打包在 App 里的同一张图。
//
//  为什么不用 NetworkImage：它只有"有图 / 没图"两种状态，图片没下回来时是一块空白；
//  关于页有 8 个头像，GitCode 抽风时整页就是一排空圆圈。这里把内置图当占位，
//  下回来再替换，视觉上最多是"图晚一点变成最新的"。
//

import SwiftUI
import AppKit
import Core

struct DomesticImage: View {
    private let path: String
    private let fallback: ImageResource

    @State private var image: NSImage?

    /// - Parameters:
    ///   - name: 分发仓库里的文件名（就是 Assets.xcassets 里 imageset 的名字）。
    ///   - fallback: 打包进 App 的兜底图。
    init(_ name: String, fallback: ImageResource) {
        self.path = DomesticAssets.aboutImagePath(name)
        self.fallback = fallback
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(fallback)
                    .resizable()
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        if let memory = DomesticImageCache.shared.image(for: path) {
            image = memory
            return
        }

        let urls: [URL] = DomesticAssets.mirrors(for: path)
        guard let first = urls.first else { return }
        // 磁盘缓存与 NetworkImage 共用一套（设置 → 其他 → 缓存里的「图标缓存」），
        // 上次会话下过的图不用重新拉。
        let cacheKey: String = ResourceCacheCenter.imageKey(first, cropRect: nil)
        if let cached = ResourceCacheCenter.shared.image(for: cacheKey) {
            DomesticImageCache.shared.store(cached, for: path)
            image = cached
            return
        }

        guard !DomesticImageCache.shared.shouldSkip(path) else { return }

        for url in urls {
            do {
                let response = try await HTTPClient.shared.get(url, timeout: 15)
                guard (200..<300).contains(response.statusCode) else {
                    throw SimpleError("返回 \(response.statusCode)")
                }
                guard let decoded = NSImage(data: response.data) else {
                    throw SimpleError("解码图片失败")
                }
                ResourceCacheCenter.shared.store(decoded, for: cacheKey)
                DomesticImageCache.shared.store(decoded, for: path)
                image = decoded
                return
            } catch let error where error.isCancellationError {
                return
            } catch {
                warn("加载头像失败 \(url.host ?? "?")：\(error.localizedDescription)")
            }
        }
        DomesticImageCache.shared.markFailed(path)
    }
}

/// 本次会话内的头像缓存。
///
/// 两层：成功的图直接留在内存里（关掉「图标缓存」时磁盘那层是空的，靠它避免每次切页重下）；
/// 失败记一个时间戳，5 分钟内不再重试——GitCode 挂掉时不该每进一次关于页就打 24 个请求，
/// 但网络恢复后也要能自己好起来，所以不是永久拉黑。
@MainActor
private final class DomesticImageCache {
    static let shared: DomesticImageCache = .init()

    private var images: [String: NSImage] = [:]
    private var failed: [String: Date] = [:]
    private let retryInterval: TimeInterval = 300

    func image(for path: String) -> NSImage? {
        images[path]
    }

    func store(_ image: NSImage, for path: String) {
        images[path] = image
        failed.removeValue(forKey: path)
    }

    func shouldSkip(_ path: String) -> Bool {
        guard let date = failed[path] else { return false }
        return Date().timeIntervalSince(date) < retryInterval
    }

    func markFailed(_ path: String) {
        failed[path] = Date()
    }
}
