//
//  BackgroundImageManager.swift
//  PCL.Swift
//
//  背景图片：扫描图片文件夹、随机挑一张、并把它交给界面。
//  对齐 PCL2 的 PageSetupUI.BackgroundRefresh。
//

import SwiftUI
import Core

/// 背景图片的唯一来源。
///
/// 两个来源：设置页里**指定的单张图片**（优先），以及数据目录 `Pictures/` 里随机一张
/// （对应 PCL2 的 `PCL/Pictures/`，只在没指定时用）。设置页可以选图、清除。
///
/// 与 PCL2 的差异只有一处：那里是把整个文件夹当候选，解不开的图只记一条日志；
/// 这里挑图时会把解不开的文件跳过，避免一张坏图让背景整个消失。
@MainActor
final class BackgroundImageManager: ObservableObject {
    static let shared: BackgroundImageManager = .init()

    /// 当前生效的背景图片。
    @Published private(set) var image: NSImage?
    /// 当前图片的路径，用于设置页显示文件名。
    @Published private(set) var fileURL: URL?
    /// 文件夹里可用的图片数量，卡片标题据此显示「（N 张）」。
    @Published private(set) var imageCount: Int = 0

    private init() {}

    static var directoryURL: URL { URLConstants.picturesDirectoryURL }

    /// 扫描文件夹，按需随机换一张。
    ///
    /// 用户在设置里**指定过**图片（`LauncherConfig.backgroundImageURL`）时优先用它，
    /// 文件夹只作为「没指定」时的随机来源。
    /// - Parameter random: 是否真的换图；false 只重新统计数量。
    func refresh(random: Bool) {
        let files: [URL] = Self.imageFiles()
        imageCount = files.count

        if let pinned = LauncherConfig.shared.backgroundImageURL {
            if let loaded = NSImage(contentsOf: pinned) {
                image = loaded
                fileURL = pinned
                return
            }
            // 文件被删/挪走了：退回文件夹随机图，免得整个背景静默消失。
            warn("指定的背景图片无法打开，已退回图片文件夹：\(pinned.path)")
            LauncherConfig.shared.backgroundImageURL = nil
        }

        guard !files.isEmpty else {
            image = nil
            fileURL = nil
            return
        }
        guard random else { return }

        for url in files.shuffled() {
            guard let loaded = NSImage(contentsOf: url) else {
                warn("背景图片无法解码，已跳过：\(url.lastPathComponent)")
                continue
            }
            image = loaded
            fileURL = url
            log("加载背景图片：\(url.path)")
            return
        }
        image = nil
        fileURL = nil
    }

    /// 选定一张图片作为背景（之后一直用它，不再随机）。
    func select(_ url: URL) {
        LauncherConfig.shared.backgroundImageURL = url
        refresh(random: true)
    }

    /// 清空背景图片：同时解除指定与删除文件夹（确认框在设置页里）。
    func clear() {
        LauncherConfig.shared.backgroundImageURL = nil
        do {
            try FileManager.default.removeItem(at: Self.directoryURL)
        } catch {
            err("清空背景图片失败：\(error.localizedDescription)")
            hint("清空背景图片失败：\(error.localizedDescription)", type: .critical)
            return
        }
        try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        image = nil
        fileURL = nil
        imageCount = 0
    }

    /// 文件夹里的候选图片。排除 ini / db（Windows 会在文件夹里塞这两个）与隐藏文件。
    private static func imageFiles() -> [URL] {
        let fileManager: FileManager = .default
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            let ext: String = url.pathExtension.lowercased()
            return ext != "ini" && ext != "db"
        }
    }
}
