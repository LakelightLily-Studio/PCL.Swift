//
//  InstanceConfigViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import Foundation
import Combine
import Core

@MainActor
class InstanceConfigViewModel: ObservableObject {
    /// 直接持有实例并观察它：改图标/改名后配置页头部会立刻刷新。
    public var instance: MinecraftInstance

    // 启动选项
    @Published public var isolation: Bool = true { didSet { scheduleAutoSave() } }
    @Published public var javaDescription: String = "无"

    // 内存
    @Published public var memoryMode: MemoryAllocationMode? { didSet { scheduleAutoSave() } }
    @Published public var jvmHeapSize: String = "" { didSet { scheduleAutoSave() } }

    // 高级选项
    @Published public var jvmArguments: String = "" { didSet { scheduleAutoSave() } }
    @Published public var gameArguments: String = "" { didSet { scheduleAutoSave() } }
    @Published public var prelaunchCommand: String = "" { didSet { scheduleAutoSave() } }
    @Published public var garbageCollector: GarbageCollectorMode? { didSet { scheduleAutoSave() } }

    /// 实例 mods 目录里的 Mod 数量，「自动配置」按它抬档（与启动时的算法一致）。
    public let modCount: Int

    public var description: String {
        if let modLoader: ModLoader = instance.modLoader {
            return "\(instance.version.description)，\(modLoader)"
        }
        return instance.version.description
    }

    /// 实例图标。直接读实例对象，改完图标后这里会跟着变。
    public var icon: InstanceIcon { instance.icon }

    public let id: String
    private var instanceCancellable: AnyCancellable?
    /// 自动保存的防抖任务。页面没有「保存设置」按钮，改动即生效。
    private var autoSaveTask: Task<Void, Never>?

    public init(instanceManager: InstanceManager, id: String) {
        self.id = id
        let instance: MinecraftInstance = instanceManager.currentRepository.instance(named: id)! // TODO: 改为安全解包
        self.instance = instance
        self.modCount = Self.countMods(in: instance)
        // 实例自己会发 objectWillChange（改图标/改名时），转发出来，
        // 否则页面读到的是旧值。
        self.instanceCancellable = instance.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        let config: MinecraftInstance.Config = instance.config
        self.isolation = config.isolation ?? true
        self.memoryMode = config.memoryMode
        self.jvmHeapSize = (config.jvmHeapSize ?? LauncherConfig.shared.resolvedMemoryMB).description
        self.jvmArguments = config.jvmArguments.joinedToArgumentLine()
        self.gameArguments = (config.gameArguments ?? []).joinedToArgumentLine()
        self.prelaunchCommand = config.prelaunchCommand ?? ""
        self.garbageCollector = config.garbageCollector
        do {
            self.javaDescription = try config.javaURL.map { try JavaSearcher.load(from: $0) }?.description ?? "自动选择"
        } catch {
            // 已配置的 Java 读不出来时只是描述缺失，页面仍可正常显示，用户可在列表里重新选择。
            self.javaDescription = "自动选择"
            warn("读取实例已配置的 Java 失败：\(error.localizedDescription)")
        }
    }

    /// 全部已安装的 Java（含当前选中的），「Java」下拉用。
    public func javaChoices() -> [JavaRuntime] {
        JavaManager.shared.javaRuntimes.sorted { $0.version > $1.version }
    }

    /// 恢复为「自动选择」：清掉实例的 Java 覆盖值，交给 JavaSearcher 按版本挑。
    @MainActor
    public func setAutomaticJava() {
        instance.config.javaURL = nil
        instance.markDirty()
        javaDescription = "自动选择"
        scheduleAutoSave()
    }

    /// 数一下实例 mods 目录里的 Mod。只用于「自动配置」的预览值，
    /// 真正启动时 MinecraftLaunchTask 会按同一套规则再数一次。
    private static func countMods(in instance: MinecraftInstance) -> Int {
        let modsURL: URL = instance.url.appending(path: "mods")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: modsURL.path) else {
            return 0
        }
        return files.filter {
            ["jar", "zip", "litemod"].contains(($0 as NSString).pathExtension.lowercased())
        }.count
    }

    @MainActor
    public func setHeapSize(_ heapSize: UInt64) {
        // 手动改数值等于切到「自定义」，否则这次修改会被 applyChanges 当成 nil 写回。
        memoryMode = .custom
        instance.config.jvmHeapSize = heapSize
        instance.markDirty()
        scheduleAutoSave()
    }

    @MainActor
    public func setJvmArguments(_ arguments: String) {
        instance.config.jvmArguments = arguments.splitToArguments()
        instance.markDirty()
        scheduleAutoSave()
    }

    @MainActor
    public func switchJava(to runtime: JavaRuntime) throws {
        if runtime.majorVersion < instance.manifest.javaVersion.majorVersion {
            throw Error.invalidJavaVersion(min: instance.manifest.javaVersion.majorVersion)
        }
        instance.config.javaURL = runtime.executableURL
        instance.markDirty()
        javaDescription = runtime.description
        scheduleAutoSave()
    }

    // MARK: - 三态写回

    /// 把界面上的值与「跟随全局」的留空语义写回实例配置。
    ///
    /// 统一在这里落盘，而不是每个控件各写一份：任何一个字段漏了
    /// markDirty，界面看起来改了、重启就丢。
    @MainActor
    func applyChanges() {
        var config: MinecraftInstance.Config = instance.config

        config.isolation = isolation ? nil : false

        config.memoryMode = memoryMode
        config.jvmHeapSize = memoryMode == .custom ? UInt64(jvmHeapSize) : nil

        // 留空即跟随全局：与 PCL2 的「留空则跟随全局设置」一致。
        config.gameArguments = gameArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : gameArguments.splitToArguments()
        config.prelaunchCommand = prelaunchCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : prelaunchCommand
        config.garbageCollector = garbageCollector

        instance.config = config
        instance.markDirty()
    }

    /// 安排一次延迟落盘。
    ///
    /// 页面去掉了「保存设置」按钮，任何改动都要自己写回磁盘。拖滑杆、连续
    /// 输入都是高频事件，逐个写盘会把 IO 打满，所以合并成"停下来 0.4s 后
    /// 存一次"。
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    @MainActor
    func save() {
        applyChanges()
        do {
            try MinecraftInstanceLoader.save(instance)
            instance.dirty = false
        } catch {
            err("保存实例配置失败：\(error.localizedDescription)")
            hint("保存实例配置失败：\(error.localizedDescription)", type: .critical)
        }
    }

    public enum Error: Swift.Error {
        case invalidJavaVersion(min: Int)
    }
}
