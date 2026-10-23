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
    @Published public var jvmHeapSize: String = ""
    @Published public var jvmArguments: String = ""
    @Published public var javaDescription: String = "无"

    // 窗口
    @Published public var windowTitle: String = ""
    @Published public var windowType: GameWindowType = .standard
    @Published public var windowWidth: String = "854"
    @Published public var windowHeight: String = "480"

    // 进程
    @Published public var launcherVisibility: LauncherVisibility = .keepVisible
    @Published public var processPriority: ProcessPriority = .normal

    // 命令与参数
    @Published public var prelaunchCommand: String = ""
    @Published public var prelaunchWaitForCompletion: Bool = false
    @Published public var gameArguments: String = ""
    @Published public var memoryOptimize: Bool = false

    /// 各字段是否跟随全局。界面上用「跟随全局」开关表示，对应 config 里的 nil。
    @Published public var followsGlobalWindowTitle: Bool = true
    @Published public var followsGlobalWindowSize: Bool = true
    @Published public var followsGlobalVisibility: Bool = true
    @Published public var followsGlobalPriority: Bool = true
    @Published public var followsGlobalPrelaunch: Bool = true
    @Published public var followsGlobalGameArguments: Bool = true
    @Published public var followsGlobalJvmArguments: Bool = true
    @Published public var followsGlobalMemoryOptimize: Bool = true

    public var description: String {
        if let modLoader: ModLoader = instance.modLoader {
            return "\(instance.version.description)，\(modLoader)"
        }
        return instance.version.description
    }

    /// 实例图标。直接读实例对象，改完图标后这里会跟着变。
    public var icon: InstanceIcon { instance.icon }

    public let id: String
    private let instanceManager: InstanceManager
    private var instanceCancellable: AnyCancellable?

    public init(instanceManager: InstanceManager, id: String) {
        self.instanceManager = instanceManager
        self.id = id
        let instance: MinecraftInstance = instanceManager.currentRepository.instance(named: id)! // TODO: 改为安全解包
        self.instance = instance
        // 实例自己会发 objectWillChange（改图标/改名时），转发出来，
        // 否则页面读到的是旧值。
        self.instanceCancellable = instance.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        let config: MinecraftInstance.Config = instance.config
        self.jvmHeapSize = config.jvmHeapSize.description
        self.jvmArguments = config.jvmArguments.joinedToArgumentLine()
        do {
            self.javaDescription = try config.javaURL.map({ try JavaSearcher.load(from: $0) })?.description ?? "无"
        } catch {
            // 已配置的 Java 读不出来时只是描述缺失，页面仍可正常显示，用户可在列表里重新选择。
            self.javaDescription = "无"
            warn("读取实例已配置的 Java 失败：\(error.localizedDescription)")
        }

        let global: LauncherConfig = .shared
        self.followsGlobalWindowTitle = config.gameWindowTitle == nil
        self.windowTitle = config.gameWindowTitle ?? global.gameWindowTitle
        self.windowType = config.gameWindowType ?? global.gameWindowType
        self.followsGlobalWindowSize = config.gameWindowWidth == nil && config.gameWindowHeight == nil
        self.windowWidth = String(config.gameWindowWidth ?? global.gameWindowWidth)
        self.windowHeight = String(config.gameWindowHeight ?? global.gameWindowHeight)
        self.followsGlobalVisibility = config.launcherVisibility == nil
        self.launcherVisibility = config.launcherVisibility ?? global.launcherVisibility
        self.followsGlobalPriority = config.processPriority == nil
        self.processPriority = config.processPriority ?? global.processPriority
        self.followsGlobalPrelaunch = config.prelaunchCommand == nil
        self.prelaunchCommand = config.prelaunchCommand ?? global.prelaunchCommand
        self.prelaunchWaitForCompletion = config.prelaunchWaitForCompletion ?? global.prelaunchWaitForCompletion
        self.followsGlobalGameArguments = config.gameArguments == nil
        self.gameArguments = (config.gameArguments ?? global.gameArguments.splitToArguments()).joinedToArgumentLine()
        self.followsGlobalJvmArguments = config.jvmArguments.isEmpty
        self.followsGlobalMemoryOptimize = config.memoryOptimize == nil
        self.memoryOptimize = config.memoryOptimize ?? global.memoryOptimize
    }

    /// 删除当前实例。
    ///
    /// 直接调 repository，不再为了一个方法去构造整个 InstanceViewModel
    /// （那会连带 4 个 Combine 订阅与一次 flatMap 类型擦除）。
    func deleteInstance() throws {
        try instanceManager.currentRepository.removeInstance(instance)
    }

    public func javaList() -> [JavaRuntime] {
        return JavaManager.shared.javaRuntimes
            .filter { $0.executableURL != instance.config.javaURL }
            .sorted { $0.version > $1.version }
    }

    @MainActor
    public func setHeapSize(_ heapSize: UInt64) {
        instance.config.jvmHeapSize = heapSize
        instance.markDirty()
    }

    @MainActor
    public func setJvmArguments(_ arguments: String) {
        instance.config.jvmArguments = arguments.splitToArguments()
        instance.markDirty()
    }

    @MainActor
    public func switchJava(to runtime: JavaRuntime) throws {
        if runtime.majorVersion < instance.manifest.javaVersion.majorVersion {
            throw Error.invalidJavaVersion(min: instance.manifest.javaVersion.majorVersion)
        }
        instance.config.javaURL = runtime.executableURL
        instance.markDirty()
        javaDescription = runtime.description
    }

    // MARK: - 三态写回

    /// 把界面上的"跟随全局"与具体值写回实例配置。
    ///
    /// 统一在这里落盘，而不是每个控件各写一份：任何一个字段漏了
    /// markDirty，界面看起来改了、重启就丢。
    @MainActor
    func applyChanges() {
        var config: MinecraftInstance.Config = instance.config

        config.gameWindowTitle = followsGlobalWindowTitle ? nil : windowTitle
        config.gameWindowType = windowType
        if followsGlobalWindowSize {
            config.gameWindowWidth = nil
            config.gameWindowHeight = nil
        } else {
            config.gameWindowWidth = Int(windowWidth)
            config.gameWindowHeight = Int(windowHeight)
        }
        config.launcherVisibility = followsGlobalVisibility ? nil : launcherVisibility
        config.processPriority = followsGlobalPriority ? nil : processPriority
        config.prelaunchCommand = followsGlobalPrelaunch ? nil : prelaunchCommand
        config.prelaunchWaitForCompletion = prelaunchWaitForCompletion
        config.gameArguments = followsGlobalGameArguments ? nil : gameArguments.splitToArguments()
        config.memoryOptimize = followsGlobalMemoryOptimize ? nil : memoryOptimize
        instance.config = config
        instance.markDirty()
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
