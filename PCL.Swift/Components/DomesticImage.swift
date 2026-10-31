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
//  取图分两步，顺序很重要：
//    1. 进场先用本地那份（本次会话的内存 → 磁盘上的图标缓存），首帧就是完整的；
//    2. 等整页入场动画彻底播完，才把云端的新图换上去。
//  动画途中换图会让卡片在动画中途重绘，新图从零尺寸插进来，
//  看起来就是"图标在页面上暂留了一瞬间"。
//

import SwiftUI
import AppKit
import Core

struct DomesticImage: View {
    @Environment(\.disableCardAppearAnimation) private var disableCardAppearAnimation: Bool

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
        // 第一步：本地那份，入场动画期间绝不去碰网络。
        // 本次会话已经拉过云端的（内存里有）就不再打网络：同一个头像没必要每进一次页面拉一次。
        if let memory = DomesticImageCache.shared.image(for: path) {
            apply(memory)
            return
        }
        // 磁盘缓存里那份只在首次进场时用：它可能已经旧了，播完动画要去云端对一次。
        if let cached = cachedImage() {
            apply(cached)
        }

        // 第二步：等整页入场动画播完。没有动画时（拖自定义主题滑杆重建视图树）直接往下走。
        if !disableCardAppearAnimation {
            do {
                try await Task.sleep(nanoseconds: UInt64(PageEntrance.window * 1_000_000_000))
            } catch {
                // 视图已经消失，没必要再拉图。
                return
            }
        }

        await refreshFromRemote()
    }

    /// 磁盘上的图标缓存（设置 → 其他 → 缓存里的「图标缓存」，关掉时没有这一层）。
    private func cachedImage() -> NSImage? {
        guard let first = DomesticAssets.mirrors(for: path).first else { return nil }
        return ResourceCacheCenter.shared.image(for: ResourceCacheCenter.imageKey(first, cropRect: nil))
    }

    private func refreshFromRemote() async {
        let urls: [URL] = DomesticAssets.mirrors(for: path)
        guard let first = urls.first else { return }
        let cacheKey: String = ResourceCacheCenter.imageKey(first, cropRect: nil)

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
                apply(decoded)
                return
            } catch let error where error.isCancellationError {
                return
            } catch {
                warn("加载头像失败 \(url.host ?? "?")：\(error.localizedDescription)")
            }
        }
        DomesticImageCache.shared.markFailed(path)
    }

    /// 换图时关掉隐式动画：卡片还在播入场，换图不该带出任何过渡。
    @MainActor
    private func apply(_ image: NSImage) {
        var transaction: Transaction = .init()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.image = image
        }
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
