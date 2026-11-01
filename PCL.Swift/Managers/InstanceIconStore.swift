//
//  InstanceIconStore.swift
//  PCL.Swift
//
//  实例图标的预设目录与取图。
//
//  图标本身放在国内分发仓库的 assets/icons/<id>.png（换图不用发版），
//  客户端按「内存 → 磁盘缓存 → 打包兜底 → 云端」的顺序取：
//  · 磁盘那层就是设置 → 其他 → 缓存里的「图标缓存」，开着才落盘；
//  · 打包兜底是 Assets.xcassets/Icons/Instance 里的同一张图，断网时选择器不会是空的。
//
//  顺序：默认 → 草方块 → 其余按创造模式物品栏的顺序（建筑方块 → 自然方块 → 功能方块
//  → 工具与实用物品 → 战斗 → 食物与饮品 → 原材料），最后是四个模组加载器的图标。
//

import SwiftUI
import AppKit
import Core

/// 一个预设图标。
struct InstancePresetIcon: Identifiable, Hashable {
    /// 仓库里的文件名（不含扩展名），也是选中后写进元数据的 id。
    let id: String
    /// 选择器里显示的名字。
    let name: String

    /// 打包在 App 里的兜底图（Assets.xcassets/Icons/Instance 里 imageset 的名字）。
    ///
    /// 这里存字符串而不是 ImageResource：同一张图既要在 SwiftUI 里显示（Image(_:)），
    /// 又要在选中时转成 NSImage 写进实例目录（NSImage(named:)），而 ImageResource 的
    /// name 是 fileprivate，取不出来。名字全部集中在这个 switch 里，加图标只改这一处。
    var asset: String {
        switch id {
        case "grass_block": "iconInstanceGrassBlock"
        case "stone": "iconInstanceStone"
        case "mossy_cobblestone": "iconInstanceMossyCobblestone"
        case "iron_block": "iconInstanceIronBlock"
        case "gold_block": "iconInstanceGoldBlock"
        case "diamond_block": "iconInstanceDiamondBlock"
        case "nether_wart_block": "iconInstanceNetherWartBlock"
        case "oak_sapling": "iconInstanceOakSapling"
        case "crafting_table": "iconInstanceCraftingTable"
        case "furnace": "iconInstanceFurnace"
        case "anvil": "iconInstanceAnvil"
        case "item_frame": "iconInstanceItemFrame"
        case "iron_pickaxe": "iconInstanceIronPickaxe"
        case "water_bucket": "iconInstanceWaterBucket"
        case "diamond_sword": "iconInstanceDiamondSword"
        case "totem_of_undying": "iconInstanceTotemOfUndying"
        case "bread": "iconInstanceBread"
        case "carrot": "iconInstanceCarrot"
        case "cooked_porkchop": "iconInstanceCookedPorkchop"
        case "golden_apple": "iconInstanceGoldenApple"
        case "potion": "iconInstancePotion"
        case "paper": "iconInstancePaper"
        case "egg": "iconInstanceEgg"
        case "neoforge": "iconInstanceNeoForge"
        case "fabric": "iconInstanceFabric"
        case "quilt": "iconInstanceQuilt"
        case "optifine": "iconInstanceOptiFine"
        default: "iconGrassBlock"
        }
    }
}


/// 图标下拉里的一个选项。
///
/// 选择器是一个普通的下拉框（MySelect），不是弹窗：打开时只显示打包在 App 里的图标，
/// **选中哪一个才去云端取哪一个**，不会一打开就把 27 张全拉下来。
enum InstanceIconChoice: Hashable, CustomStringConvertible {
    /// 按加载器自动推导（没有加载器就是草方块）。
    case automatic
    /// 预设图标。
    case preset(InstancePresetIcon)
    /// 自己挑一张图片。
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
@MainActor
final class InstanceIconStore {
    static let shared: InstanceIconStore = .init()

    /// 图标集的版本号。
    ///
    /// 云端路径是固定的 assets/icons/<id>.png，换图不改名；客户端按 URL 做磁盘缓存，
    /// 所以换图后必须把这个号一起改掉，老用户的旧图才会被绕开、重新拉一次。
    /// 改这里的同时记得把新图推到国内仓库（Scripts/publish-dist.sh）。
    static let iconSetVersion: String = "20261101"

    /// 本次会话已经拿到的图（云端那份，或磁盘缓存里那份）。
    private var memory: [String: NSImage] = [:]
    /// 拉取失败的时间戳，5 分钟内不再重试（与「更多」页头像同一套策略）。
    private var failed: [String: Date] = [:]
    private let retryInterval: TimeInterval = 300

    private init() {}

    /// 立刻能显示的那份：内存 → 磁盘缓存 → 打包兜底。
    func immediateImage(for icon: InstancePresetIcon) -> NSImage? {
        if let image = memory[icon.id] { return image }
        if let key = cacheKey(for: icon), let cached = ResourceCacheCenter.shared.image(for: key) {
            memory[icon.id] = cached
            return cached
        }
        return NSImage(named: icon.asset)
    }

    /// 去云端要一份新的。拿到就更新内存并落盘（开关关掉时只留内存）。
    /// - Returns: 是否拿到了新图。
    @discardableResult
    func refresh(_ icon: InstancePresetIcon) async -> Bool {
        guard shouldRetry(icon) else { return false }
        let path: String = DomesticAssets.instanceIconPath(icon.id)
        guard let key = cacheKey(for: icon) else { return false }

        for url in DomesticAssets.mirrors(for: path, cacheBust: Self.iconSetVersion) {
            do {
                let response = try await HTTPClient.shared.get(url, timeout: 15)
                guard (200..<300).contains(response.statusCode) else {
                    throw SimpleError("返回 \(response.statusCode)")
                }
                guard let image = NSImage(data: response.data) else {
                    throw SimpleError("解码图片失败")
                }
                memory[icon.id] = image
                failed.removeValue(forKey: icon.id)
                ResourceCacheCenter.shared.store(image, for: key)
                return true
            } catch let error where error.isCancellationError {
                return false
            } catch {
                warn("加载实例图标失败 \(url.host ?? "?")：\(error.localizedDescription)")
            }
        }
        failed[icon.id] = Date()
        return false
    }

    /// 选中某个预设图标时，把它写进实例目录要用的那张图。
    /// 云端优先，拿不到就退回打包的那份，保证离线也能换图标。
    func imageForSaving(_ icon: InstancePresetIcon) async -> NSImage? {
        if let image = memory[icon.id] { return image }
        _ = await refresh(icon)
        return memory[icon.id] ?? immediateImage(for: icon)
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
