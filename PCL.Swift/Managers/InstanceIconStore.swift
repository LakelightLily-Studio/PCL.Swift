//
//  InstanceIconStore.swift
//  PCL.Swift
//
//  实例图标的预设目录与取图。
//
//  图标本身放在国内分发仓库的 assets/icons/<id>.png（换图不用发版）。**App 里不打包这些图**：
//  列表只写死 id 与名字，缩略图统一从云端拉，拿到之后按「内存 → 磁盘缓存」留着，
//  下次不再重复请求——除非本地那份丢了（缓存被清、文件被删）才重新拉。
//  · 磁盘那层就是设置 → 其他 → 缓存里的「图标缓存」，开着才落盘；
//  · 一次拉 6 个，27 个图标四批拉完，不把 GitCode 打满。
//
//  顺序：默认 → 草方块 → 其余按创造模式物品栏的顺序（建筑方块 → 自然方块 → 功能方块
//  → 工具与实用物品 → 战斗 → 食物与饮品 → 原材料），最后是四个模组加载器的图标。
//

import SwiftUI
import AppKit
import Core

/// 一个预设图标。
///
/// 只有 id 与名字：图是运行时从云端拉的，不打包进 App。
struct InstancePresetIcon: Identifiable, Hashable {
    /// 仓库里的文件名（不含扩展名），也是选中后写进元数据的 id。
    let id: String
    /// 下拉里显示的名字。
    let name: String
}

/// 图标下拉里的一个选项。
enum InstanceIconChoice: Hashable, CustomStringConvertible {
    /// 按加载器自动推导（没有加载器就是草方块）。
    case automatic
    /// 预设图标。
    case preset(InstancePresetIcon)
    /// 自己填 URL 或挑一张本地图片。
    case custom

    var description: String {
        switch self {
        case .automatic: "默认"
        case .preset(let icon): icon.name
        case .custom: "自定义…"
        }
    }
}

enum InstanceIconCatalog {
    /// 预设图标，顺序即选择器里的顺序（「默认」不在其中，它固定排第一项）。
    static let presets: [InstancePresetIcon] = [
        // 草方块固定排第二（第一格是「默认」）。
        .init(id: "grass_block", name: "草方块"),
        // 以下按创造模式物品栏的顺序：建筑方块 → 自然方块 → 功能方块
        // → 工具与实用物品 → 战斗 → 食物与饮品 → 原材料。
        .init(id: "stone", name: "石头"),
        .init(id: "mossy_cobblestone", name: "苔石"),
        .init(id: "iron_block", name: "铁块"),
        .init(id: "gold_block", name: "金块"),
        .init(id: "diamond_block", name: "钻石块"),
        .init(id: "nether_wart_block", name: "下界疣块"),
        .init(id: "oak_sapling", name: "橡树树苗"),
        .init(id: "crafting_table", name: "工作台"),
        .init(id: "furnace", name: "熔炉"),
        .init(id: "anvil", name: "铁砧"),
        .init(id: "item_frame", name: "物品展示框"),
        .init(id: "iron_pickaxe", name: "铁镐"),
        .init(id: "water_bucket", name: "水桶"),
        .init(id: "diamond_sword", name: "钻石剑"),
        .init(id: "totem_of_undying", name: "不死图腾"),
        .init(id: "bread", name: "面包"),
        .init(id: "carrot", name: "胡萝卜"),
        .init(id: "cooked_porkchop", name: "熟猪排"),
        .init(id: "golden_apple", name: "金苹果"),
        .init(id: "potion", name: "药水"),
        .init(id: "paper", name: "纸"),
        .init(id: "egg", name: "鸡蛋"),
        // 模组加载器的图标不属于创造模式物品栏，统一排在最后。
        .init(id: "neoforge", name: "NeoForge"),
        .init(id: "fabric", name: "Fabric"),
        .init(id: "quilt", name: "Quilt"),
        .init(id: "optifine", name: "OptiFine"),
    ]

    static func icon(id: String) -> InstancePresetIcon? {
        presets.first { $0.id == id }
    }
}

/// 实例图标的取图与缓存。
///
/// 是个 ObservableObject：缩略图是异步拉回来的，页面靠它刷新下拉里的图。
@MainActor
final class InstanceIconStore: ObservableObject {
    static let shared: InstanceIconStore = .init()

    /// 图标集的版本号。
    ///
    /// 云端路径是固定的 assets/icons/<id>.png，换图不改名；客户端按 URL 做磁盘缓存，
    /// 所以换图后必须把这个号一起改掉，老用户的旧图才会被绕开、重新拉一次。
    /// 改这里的同时记得把新图推到国内仓库（Scripts/publish-dist.sh）。
    static let iconSetVersion: String = "20261101"

    /// 已经拿到的缩略图（内存层）。键是图标的 id。
    @Published private(set) var images: [String: NSImage] = [:]
    /// 拉取失败的时间戳，5 分钟内不再重试（与「更多」页头像同一套策略）。
    private var failed: [String: Date] = [:]
    private let retryInterval: TimeInterval = 300
    /// 正在拉的图标，避免同一张图并发拉两次。
    private var loading: Set<String> = []

    private init() {}

    /// 内存里那张（磁盘那份在 load 里翻）。
    func image(for icon: InstancePresetIcon) -> NSImage? {
        images[icon.id]
    }

    /// 一次性把所有缩略图拉到本地。
    ///
    /// 已经在内存 / 磁盘缓存里的直接跳过，所以反复进出页面不会重复请求；
    /// 只有本地那份真的丢了（清缓存、文件被删）才会重新拉。
    func preloadAll() async {
        let missing: [InstancePresetIcon] = InstanceIconCatalog.presets.filter { images[$0.id] == nil }
        guard !missing.isEmpty else { return }
        // 一次 6 个：27 张图四批就够，别把 GitCode 打满。
        for start in stride(from: 0, to: missing.count, by: 6) {
            let batch: [InstancePresetIcon] = Array(missing[start..<min(start + 6, missing.count)])
            await withTaskGroup(of: Void.self) { group in
                for icon in batch {
                    group.addTask { await self.load(icon) }
                }
            }
        }
    }

    /// 拿一张图：内存 → 磁盘缓存 → 云端。已有的不再请求。
    func load(_ icon: InstancePresetIcon) async {
        if images[icon.id] != nil { return }
        let key: String? = cacheKey(for: icon)
        if let key, let cached = ResourceCacheCenter.shared.image(for: key) {
            images[icon.id] = cached
            return
        }
        guard shouldRetry(icon), !loading.contains(icon.id) else { return }
        loading.insert(icon.id)
        defer { loading.remove(icon.id) }

        let path: String = DomesticAssets.instanceIconPath(icon.id)
        for url in DomesticAssets.mirrors(for: path, cacheBust: Self.iconSetVersion) {
            do {
                let response = try await HTTPClient.shared.get(url, timeout: 15)
                guard (200..<300).contains(response.statusCode) else {
                    throw SimpleError("返回 \(response.statusCode)")
                }
                guard let image = NSImage(data: response.data) else {
                    throw SimpleError("解码图片失败")
                }
                images[icon.id] = image
                failed.removeValue(forKey: icon.id)
                if let key {
                    ResourceCacheCenter.shared.store(image, for: key)
                }
                return
            } catch let error where error.isCancellationError {
                return
            } catch {
                warn("加载实例图标失败 \(url.host ?? "?")：\(error.localizedDescription)")
            }
        }
        failed[icon.id] = Date()
    }

    /// 选中某个预设图标时，写进实例目录要用的那张图。
    ///
    /// 本地已有（内存 / 磁盘）就直接用；没有才去云端要——**不再有打包兜底**，
    /// 拿不到就返回 nil，由调用方提示失败。
    func imageForSaving(_ icon: InstancePresetIcon) async -> NSImage? {
        if let image = images[icon.id] { return image }
        await load(icon)
        return images[icon.id]
    }

    private func cacheKey(for icon: InstancePresetIcon) -> String? {
        let path: String = DomesticAssets.instanceIconPath(icon.id)
        guard let first = DomesticAssets.mirrors(for: path, cacheBust: Self.iconSetVersion).first else { return nil }
        return ResourceCacheCenter.imageKey(first, cropRect: nil)
    }

    private func shouldRetry(_ icon: InstancePresetIcon) -> Bool {
        guard let date = failed[icon.id] else { return true }
        return Date().timeIntervalSince(date) >= retryInterval
    }
}
