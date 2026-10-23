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
    /// 除 jvmHeapSize / javaURL / jvmArguments 外全部是可选的"覆盖值"：
    /// nil 表示跟随全局设置（LauncherConfig 里的同名字段）。用三态而不是
    /// 拷贝全局值，是因为全局改动要能传导到所有没单独设过的实例。
    public struct Config: Codable {
        public var jvmHeapSize: UInt64
        public var javaURL: URL?
        public var jvmArguments: [String]

        public var gameWindowTitle: String?
        public var gameWindowType: GameWindowType?
        public var gameWindowWidth: Int?
        public var gameWindowHeight: Int?
        public var launcherVisibility: LauncherVisibility?
        public var processPriority: ProcessPriority?
        public var prelaunchCommand: String?
        public var prelaunchWaitForCompletion: Bool?
        public var gameArguments: [String]?
        public var memoryOptimize: Bool?

        public static let `default`: Config = .init(jvmHeapSize: 4096, javaURL: nil)

        public init(jvmHeapSize: UInt64, javaURL: URL?, jvmArguments: [String] = []) {
            self.jvmHeapSize = jvmHeapSize
            self.javaURL = javaURL
            self.jvmArguments = jvmArguments
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.jvmHeapSize = try container.decode(UInt64.self, forKey: .jvmHeapSize)
            self.javaURL = try container.decodeIfPresent(URL.self, forKey: .javaURL)
            self.jvmArguments = try container.decodeIfPresent([String].self, forKey: .jvmArguments) ?? []

            self.gameWindowTitle = try container.decodeIfPresent(String.self, forKey: .gameWindowTitle)
            self.gameWindowType = try? container.decodeIfPresent(GameWindowType.self, forKey: .gameWindowType)
            self.gameWindowWidth = try container.decodeIfPresent(Int.self, forKey: .gameWindowWidth)
            self.gameWindowHeight = try container.decodeIfPresent(Int.self, forKey: .gameWindowHeight)
            self.launcherVisibility = try? container.decodeIfPresent(LauncherVisibility.self, forKey: .launcherVisibility)
            self.processPriority = try? container.decodeIfPresent(ProcessPriority.self, forKey: .processPriority)
            self.prelaunchCommand = try container.decodeIfPresent(String.self, forKey: .prelaunchCommand)
            self.prelaunchWaitForCompletion = try container.decodeIfPresent(Bool.self, forKey: .prelaunchWaitForCompletion)
            self.gameArguments = try container.decodeIfPresent([String].self, forKey: .gameArguments)
            self.memoryOptimize = try container.decodeIfPresent(Bool.self, forKey: .memoryOptimize)
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
