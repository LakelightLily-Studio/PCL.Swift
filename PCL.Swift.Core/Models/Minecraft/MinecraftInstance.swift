//
//  MinecraftInstance.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/4/15.
//

import Foundation
import AppKit

public class MinecraftInstance: ObservableObject, Hashable, Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let version: MinecraftVersion
    public let modLoader: ModLoader?
    public let manifest: ClientManifest

    public var config: Config

    /// 实例图标。所有需要显示实例图标的地方都从这里取。
    ///
    /// 单独抽出来是因为它有三个来源（自定义图片 / 加载器图标 / 草方块），
    /// 且自定义图片要在多处同步刷新——之前每个页面各算一遍，
    /// 改完图标后别的页面还显示旧值。
    public var icon: InstanceIcon {
        if let customIconURL, let image = NSImage(contentsOf: customIconURL) {
            return .custom(image)
        }
        if let modLoader {
            return .loader(modLoader)
        }
        return .fallback
    }

    /// 用户在"版本修改"里填的显示名。nil 表示沿用文件夹名。
    ///
    /// 不改文件夹名：name 同时是实例目录名、清单文件名与启动参数 version_name 的来源，
    /// 改名要连带搬目录、改清单引用，失败会留下半截实例。显示名只影响界面。
    public var displayName: String?
    /// 用户自定义的实例图标文件路径。nil 表示按加载器推导。
    public var customIconURL: URL?
    /// 用户自定义的实例描述。
    public var customDescription: String?
    /// 是否加入收藏夹。
    public var isFavorite: Bool
    /// 用户自定义的分类名。nil 表示未分类。
    public var category: String?

    public var dirty: Bool

    /// 界面展示用的名字：优先显示名，其次文件夹名。
    public var title: String { displayName?.isEmpty == false ? displayName! : name }
    public var name: String { url.lastPathComponent }
    public var manifestURL: URL { url.appending(path: "\(name).json") }

    public init(
        id: UUID,
        url: URL,
        version: MinecraftVersion,
        modLoader: ModLoader?,
        manifest: ClientManifest,
        config: Config,
        displayName: String? = nil,
        customIconURL: URL? = nil,
        customDescription: String? = nil,
        isFavorite: Bool = false,
        category: String? = nil,
        dirty: Bool = false
    ) {
        self.id = id
        self.url = url
        self.version = version
        self.modLoader = modLoader
        self.manifest = manifest
        self.config = config
        self.displayName = displayName
        self.customIconURL = customIconURL
        self.customDescription = customDescription
        self.isFavorite = isFavorite
        self.category = category
        self.dirty = dirty
    }

    /// 标记实例有未落盘的改动。
    ///
    /// 同时广播一次变更：图标、显示名、收藏状态都写在实例对象上，
    /// 而实例被多个页面分别持有，不发通知的话改完只有当前页刷新。
    public func markDirty() {
        self.dirty = true
        objectWillChange.send()
    }


    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MinecraftInstance, rhs: MinecraftInstance) -> Bool {
        return lhs.id == rhs.id
    }

    /// 实例级配置。
    ///
    /// 字段全部是可选的"覆盖值"：nil 表示跟随全局设置（LauncherConfig 里的
    /// 同名字段）。用三态而不是拷贝全局值，是因为全局改动要能传导到所有没单独设过的实例。
    ///
    /// jvmHeapSize 也走三态：设置 → 启动 →「内存分配」支持自动配置后，
    /// 实例必须能表达"跟着全局走"。老配置文件里都有这个键，解码后仍是显式值，
    /// 升级不会悄悄改掉任何已有实例的内存。
    public struct Config: Codable {
        /// 实例独立分配的内存（MB），只在 memoryMode 为 custom 时使用。
        public var jvmHeapSize: UInt64?
        /// 实例的内存分配方式：nil 表示跟随全局，「自动配置」按 Mod 量现算。
        ///
        /// 老配置里没有这个键，但通常带着 jvmHeapSize；解码时会把它认作 custom，
        /// 所以升级不会把用户单独设过的内存悄悄改回「跟随全局」。
        public var memoryMode: MemoryAllocationMode?
        public var javaURL: URL?
        public var jvmArguments: [String]

        /// 版本隔离。nil / true 表示隔离（独立目录）；false 表示与仓库根目录共享存档、Mod。
        public var isolation: Bool?
        /// 实例级垃圾回收器覆盖。nil 表示跟随全局。
        public var garbageCollector: GarbageCollectorMode?

        public var gameWindowType: GameWindowType?
        public var gameWindowWidth: Int?
        public var gameWindowHeight: Int?
        public var launcherVisibility: LauncherVisibility?
        public var processPriority: ProcessPriority?
        public var prelaunchCommand: String?
        public var gameArguments: [String]?

        public static let `default`: Config = .init(jvmHeapSize: nil, javaURL: nil)

        public init(jvmHeapSize: UInt64? = nil, javaURL: URL?, jvmArguments: [String] = []) {
            self.jvmHeapSize = jvmHeapSize
            self.memoryMode = jvmHeapSize == nil ? nil : .custom
            self.javaURL = javaURL
            self.jvmArguments = jvmArguments
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.jvmHeapSize = try container.decodeIfPresent(UInt64.self, forKey: .jvmHeapSize)
            // 老配置只有 jvmHeapSize：有值就当作用户选过「自定义」，
            // 否则会从"实例自己分配"悄悄变成"跟随全局"。
            self.memoryMode = (try? container.decodeIfPresent(MemoryAllocationMode.self, forKey: .memoryMode))
                ?? (self.jvmHeapSize == nil ? nil : .custom)
            self.javaURL = try container.decodeIfPresent(URL.self, forKey: .javaURL)
            self.jvmArguments = try container.decodeIfPresent([String].self, forKey: .jvmArguments) ?? []

            self.isolation = try container.decodeIfPresent(Bool.self, forKey: .isolation)
            self.garbageCollector = try? container.decodeIfPresent(GarbageCollectorMode.self, forKey: .garbageCollector)

            self.gameWindowType = try? container.decodeIfPresent(GameWindowType.self, forKey: .gameWindowType)
            self.gameWindowWidth = try container.decodeIfPresent(Int.self, forKey: .gameWindowWidth)
            self.gameWindowHeight = try container.decodeIfPresent(Int.self, forKey: .gameWindowHeight)
            self.launcherVisibility = try? container.decodeIfPresent(LauncherVisibility.self, forKey: .launcherVisibility)
            self.processPriority = try? container.decodeIfPresent(ProcessPriority.self, forKey: .processPriority)
            self.prelaunchCommand = try container.decodeIfPresent(String.self, forKey: .prelaunchCommand)
            self.gameArguments = try container.decodeIfPresent([String].self, forKey: .gameArguments)
        }
    }
}

public extension JavaSearcher {
    static func pick(for instance: MinecraftInstance) -> JavaRuntime? {
        let systemArch: Architecture = .systemArchitecture()
        let instanceNeedsX64 = instance.version < .init("1.7.2")

        func score(of javaRuntime: JavaRuntime) -> Int {
            var score = 0
            if javaRuntime.architecture == (instance.version > .init("1.7.2") ? systemArch : .x64) { score += 3 }
            if javaRuntime.majorVersion == instance.manifest.javaVersion.majorVersion { score += 2 }
            if javaRuntime.type == .jdk { score += 1 }
            return score
        }

        let javaRuntimes = JavaManager.shared.javaRuntimes.lazy
            .filter { $0.majorVersion >= instance.manifest.javaVersion.majorVersion && !(systemArch == .x64 && $0.architecture == .arm64) }
            .filter { !(instanceNeedsX64 && $0.architecture != .x64)  }

        return javaRuntimes.max(by: { score(of: $0) < score(of: $1) })
    }
}

/// 实例图标的三种来源。
///
/// 放在 Core 里而不是 App：Core 已经有 AppKit 依赖（图标解码要用 NSImage），
/// 而 InstanceConfigViewModel 这类跨层调用方不该各写一份"自定义优先"的判断。
public enum InstanceIcon {
    /// 用户指定的图片。
    case custom(NSImage)
    /// 按模组加载器推导的图标。
    case loader(ModLoader)
    /// 都没有时的兜底（草方块）。
    case fallback

    /// 是否来自用户自定义图片。
    public var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}
