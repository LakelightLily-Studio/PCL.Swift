//
//  URLConstants.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/8.
//

import Foundation

public struct URLConstants {
    public static let contentsURL: URL = Bundle.main.bundleURL.appending(path: "Contents")
    public static let resourcesURL: URL = contentsURL.appending(path: "Resources")
    
    /// 数据目录。
    ///
    /// 2.0 起由 `PCL.Mac.Refactor` 改名为 `PCL.Swift`。改名会让老用户丢掉
    /// 账号、实例列表与全部设置，所以首次启动时把旧目录整体搬过来——只搬一次，
    /// 之后旧目录不再被引用。
    public static let applicationSupportURL: URL = {
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        let current = root.appending(path: "PCL.Swift")
        let legacy = root.appending(path: "PCL.Mac.Refactor")
        if migrateLegacyDirectoryIfNeeded(from: legacy, to: current) { return current }
        // 迁移失败时继续用旧目录，宁可路径难看也不能让用户的数据"消失"。
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: legacy.path),
           !fileManager.fileExists(atPath: current.path) {
            return legacy
        }
        return current
    }()
    
    /// 旧版本（PCL.Mac.Refactor）的数据目录，仅用于迁移与提示。
    public static let legacyApplicationSupportURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/PCL.Mac.Refactor")
    
    /// 把旧数据目录搬到新位置。已存在新目录时不动任何东西。
    private static func migrateLegacyDirectoryIfNeeded(from legacy: URL, to current: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: current.path) else { return false }
        do {
            try fileManager.moveItem(at: legacy, to: current)
            print("已将数据目录从 \(legacy.lastPathComponent) 迁移到 \(current.lastPathComponent)")
            return true
        } catch {
            print("数据目录迁移失败，继续使用旧目录：\(error.localizedDescription)")
            return false
        }
    }
    public static let logsDirectoryURL: URL = applicationSupportURL.appending(path: "Logs")
    public static let configURL: URL = applicationSupportURL.appending(path: "config.json")
    public static let cacheURL: URL = applicationSupportURL.appending(path: "Caches")
    public static let tempURL: URL = applicationSupportURL.appending(path: "Temp")
    public static let authlibInjectorURL: URL = applicationSupportURL.appending(path: "authlib-injector.jar")
    public static let easyTierURL: URL = applicationSupportURL.appending(path: "EasyTier")
    /// 背景图片目录（对齐 PCL2 的 PCL/Pictures）：放进去的图片会在启动时随机挑一张。
    public static let picturesDirectoryURL: URL = applicationSupportURL.appending(path: "Pictures")
    
    public static func createDirectories() throws {
        let fileManager: FileManager = .default
        try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: easyTierURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: picturesDirectoryURL, withIntermediateDirectories: true)
    }
}
