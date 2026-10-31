//
//  InstanceOverviewViewModel.swift
//  PCL.Swift
//
//  实例概览页的数据与元数据修改。
//

import Foundation
import AppKit
import Combine
import Core

@MainActor
class InstanceOverviewViewModel: ObservableObject {
    public private(set) var instance: MinecraftInstance
    /// 自定义图标解码结果。nil 表示使用回退图标。
    @Published public private(set) var iconImage: NSImage?
    /// 目录列表。
    ///
    /// 缓存成存储属性而不是计算属性：每个条目都要做一次 FileManager.fileExists，
    /// 8 个目录就是 8 次同步磁盘 I/O。计算属性会在每次 body 求值时重跑一遍，
    /// 卡片入场动画期间每帧都求值，这正是实例设置页卡顿的来源。
    @Published public private(set) var folders: [Folder] = []

    private let instanceManager: InstanceManager
    private var instanceCancellable: AnyCancellable?

    public var instanceName: String { instance.name }
    public var displayTitle: String { instance.title }
    public var subtitle: String {
        if let modLoader: ModLoader = instance.modLoader {
            return "\(instance.version.id)，\(modLoader)"
        }
        return instance.version.id
    }
    public var descriptionText: String {
        if let custom = instance.customDescription, !custom.isEmpty { return custom }
        return "没有填写描述。"
    }
    /// 描述输入框的初始内容（不含占位文案）。
    public var customDescriptionText: String { instance.customDescription ?? "" }
    public var isFavorite: Bool { instance.isFavorite }
    public var category: String? { instance.category }
    public var fallbackIcon: ImageResource {
        instance.modLoader?.icon ?? .iconGrassBlock
    }

    /// 「默认」那一格的图标：按加载器推导，没有加载器就是草方块。
    public var automaticIcon: InstanceIcon {
        if let modLoader = instance.modLoader { return .loader(modLoader) }
        return .fallback
    }

    /// 当前选中的预设图标 id；用户自己选的图片没有 id，为 nil。
    public var selectedIconID: String? { instance.customIconName }

    /// 当前图标是不是用户自己选的图片。
    public var isCustomIconSelected: Bool {
        instance.customIconURL != nil && instance.customIconName == nil
    }

    public init(instanceManager: InstanceManager, id: String) {
        self.instanceManager = instanceManager
        let instance: MinecraftInstance = instanceManager.currentRepository.instance(named: id)!
        self.instance = instance
        self.iconImage = Self.loadIcon(for: instance)
        // 转发实例自身的变更：改名/改图标后页面要立刻刷新。
        self.instanceCancellable = instance.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.iconImage = Self.loadIcon(for: instance)
        }
        self.folders = Self.makeFolders(for: instance)
    }

    // MARK: - 目录

    struct Folder: Identifiable {
        let key: String
        let title: String
        let relativePath: String
        let url: URL
        let exists: Bool
        /// 点击时是否自动创建目录。存档、截图这类目录游戏首次用到才创建，
        /// 点进去时顺手建出来比提示"不存在"更符合预期。
        let createsOnOpen: Bool

        var id: String { key }
    }

    /// 重新扫描目录状态。文件系统可能在外部被改动（例如游戏自己建了 logs）。
    func refreshFolders() {
        folders = Self.makeFolders(for: instance)
    }

    /// 概览页展示的目录列表。
    ///
    /// 只列用户真正会去找的几个：存档、Mod、资源包、光影包、截图、日志、崩溃报告。
    /// 全部列出来会让这一屏变成文件浏览器，反而不好用。
    private static func makeFolders(for instance: MinecraftInstance) -> [Folder] {
        let root: URL = instance.url
        let entries: [(String, String, String, Bool)] = [
            ("saves", "存档文件夹", "saves", true),
            ("mods", "Mod 文件夹", "mods", true),
            ("resourcepacks", "资源包文件夹", "resourcepacks", true),
            ("shaderpacks", "光影包文件夹", "shaderpacks", true),
            ("screenshots", "截图文件夹", "screenshots", true),
            ("logs", "日志文件夹", "logs", true),
            ("crashReports", "崩溃报告文件夹", "crash-reports", true),
            ("root", "版本文件夹", ".", false)
        ]
        return entries.map { key, title, path, createsOnOpen in
            let url: URL = path == "." ? root : root.appending(path: path)
            return .init(
                key: key,
                title: title,
                relativePath: path == "." ? instance.name : "\(instance.name)/\(path)",
                url: url,
                exists: FileManager.default.fileExists(atPath: url.path),
                createsOnOpen: createsOnOpen
            )
        }
    }

    func open(_ folder: Folder) {
        if folder.createsOnOpen && !folder.exists {
            do {
                try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
            } catch {
                err("创建目录 \(folder.url.lastPathComponent) 失败：\(error.localizedDescription)")
                hint("创建目录失败：\(error.localizedDescription)", type: .critical)
                return
            }
        }
        guard FileManager.default.fileExists(atPath: folder.url.path) else {
            hint("\(folder.title)不存在！", type: .critical)
            return
        }
        NSWorkspace.shared.open(folder.url)
    }

    // MARK: - 元数据

    /// 删除当前实例。
    ///
    /// 原版的版本设置页没有这颗按钮（删除在版本列表的右键菜单里），
    /// 本启动器没有右键菜单，所以放在「概览 → 操作」，别让功能凭空消失。
    @MainActor
    func deleteInstance() throws {
        try instanceManager.currentRepository.removeInstance(instance)
    }

    func toggleFavorite() {
        instance.isFavorite.toggle()
        instance.markDirty()
        save()
    }

    func setDisplayName(_ name: String) {
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 留空即恢复为"跟随文件夹名"，而不是写一个空字符串进去。
        instance.displayName = trimmed.isEmpty ? nil : trimmed
        instance.markDirty()
        save()
    }

    func setDescription(_ text: String) {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        instance.customDescription = trimmed.isEmpty ? nil : trimmed
        instance.markDirty()
        save()
    }

    func setCategory(_ text: String) {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        instance.category = trimmed.isEmpty ? nil : trimmed
        instance.markDirty()
        save()
    }

    func setIcon(_ url: URL) {
        // 把图标复制进实例目录，而不是记住外部路径：外部文件随时会被删，
        // 记住路径等于让图标在某个时刻静默消失。
        let destination: URL = instance.url.appending(path: ".clicon.\(url.pathExtension)")
        do {
            if let old = instance.customIconURL, old != destination {
                try? FileManager.default.removeItem(at: old)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            instance.customIconURL = destination
            // 用户自己选的图片没有预设 id，选择器里据此高亮「自定义…」那一格。
            instance.customIconName = nil
            // markDirty 会广播 objectWillChange，所有观察该实例的页面一起刷新。
            instance.markDirty()
            save()
            iconImage = Self.loadIcon(for: instance)
            hint("图标已更新！", type: .finish)
        } catch {
            err("设置实例图标失败：\(error.localizedDescription)")
            hint("设置实例图标失败：\(error.localizedDescription)", type: .critical)
        }
    }

    /// 应用一个预设图标（选择器里的那些方块 / 物品）。
    ///
    /// 与自定义图片同一条路：图**复制**进实例目录存成 .clicon.png，
    /// 额外记一个 customIconName，只用于在选择器里标出当前是哪一格。
    func setIcon(_ icon: InstancePresetIcon) async {
        guard let image = await InstanceIconStore.shared.imageForSaving(icon),
              let data = Self.pngData(of: image) else {
            hint("图标加载失败，请检查网络后重试。", type: .critical)
            return
        }
        let destination: URL = instance.url.appending(path: ".clicon.png")
        do {
            if let old = instance.customIconURL, old != destination {
                try? FileManager.default.removeItem(at: old)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination)
            instance.customIconURL = destination
            instance.customIconName = icon.id
            instance.markDirty()
            save()
            iconImage = Self.loadIcon(for: instance)
            hint("图标已更新！", type: .finish)
        } catch {
            err("设置实例图标失败：\(error.localizedDescription)")
            hint("设置实例图标失败：\(error.localizedDescription)", type: .critical)
        }
    }

    /// 清空自定义图标，回到按加载器推断的默认图标。
    func clearIcon() {
        if let old = instance.customIconURL {
            do {
                try FileManager.default.removeItem(at: old)
            } catch {
                warn("删除旧图标失败：\(error.localizedDescription)")
            }
        }
        instance.customIconURL = nil
        instance.customIconName = nil
        instance.markDirty()
        save()
        iconImage = Self.loadIcon(for: instance)
    }

    /// 仓库里已经用过的分类，供「分类」下拉选择。
    var availableCategories: [String] {
        let instances: [MinecraftInstance] = Array((instanceManager.currentRepository.instances ?? [:]).values)
        let categories: [String] = instances.compactMap(\.category)
        return Array(Set(categories.filter { !$0.isEmpty })).sorted()
    }

    /// 按 key 取目录，快捷方式卡按需取用。
    func folder(_ key: String) -> Folder? {
        folders.first { $0.key == key }
    }

    /// 重新校验并补齐实例文件。
    func repair() {
        let task: MyTask<MinecraftInstallTask.Model> = MinecraftInstallTask.createRepair(
            instance: instance,
            repository: instanceManager.currentRepository
        )
        TaskManager.shared.execute(task: task)
        AppRouter.shared.append(.tasks)
    }

    private func save() {
        do {
            try MinecraftInstanceLoader.save(instance)
            instance.dirty = false
        } catch {
            err("保存实例配置失败：\(error.localizedDescription)")
            hint("保存实例配置失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private static func loadIcon(for instance: MinecraftInstance) -> NSImage? {
        guard let url = instance.customIconURL else { return nil }
        return NSImage(contentsOf: url)
    }

    /// 把内存里的图转成 PNG 数据：写进实例目录的那份要是真实文件，不能只存内存。
    private static func pngData(of image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
