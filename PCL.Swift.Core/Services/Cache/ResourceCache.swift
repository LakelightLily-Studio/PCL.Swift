//
//  ResourceCache.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/6/7.
//

import Foundation

public class ResourceCache {
    private static var _shared: ResourceCache?

    /// 全局实例。由 `AppDelegate.applicationDidFinishLaunching` 创建。必须在启动阶段由 `AppDelegate` 注入后才能访问：
    /// 早于注入访问会立刻在注入点给出可定位的失败，而不是在某个随机调用点崩溃。
    public static var shared: ResourceCache {
        guard let instance = _shared else {
            fatalError("ResourceCache.shared 在注入之前被访问，请检查 AppDelegate 的初始化顺序。")
        }
        return instance
    }

    public static func install(_ instance: ResourceCache) {
        _shared = instance
    }
    
    private let cacheFileURL: URL
    private let iconCacheDirectory: URL
    private var cacheMap: [String: Resource]
    
    public init(cacheDirectory: URL) {
        self.cacheFileURL = cacheDirectory.appending(path: "resource_cache.json")
        self.iconCacheDirectory = cacheDirectory.appending(path: "resource_icon")
        
        if FileManager.default.fileExists(atPath: cacheFileURL.path) {
            do {
                let data = try Data(contentsOf: cacheFileURL)
                self.cacheMap = try JSONDecoder.shared.decode([String: Resource].self, from: data)
            } catch {
                err("缓存文件加载失败：\(error.localizedDescription)")
                try? FileManager.default.removeItem(at: cacheFileURL)
                self.cacheMap = [:]
            }
        } else {
            self.cacheMap = [:]
        }
    }
    
    public func resource(forHash hash: String) -> Resource? { cacheMap[hash] }
    
    public func store(_ resource: Resource, forHash hash: String) { cacheMap[hash] = resource }
    
    public func icon(forHash globalHash: String) throws -> Data? {
        let url = url(of: globalHash)
        if FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        return nil
    }
    
    public func store(_ iconData: Data, relativePath: String, fileHash: String) throws -> String {
        let globalHash = globalHash(of: relativePath, with: fileHash)
        let url = url(of: globalHash)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try iconData.write(to: url)
        return globalHash
    }
    
    /// 释放内存中的图标数据。
    ///
    /// 图标是解码后的位图，几百个 Mod 加起来能占几十 MB。磁盘上的缓存文件
    /// 保留不动，下次需要时按需重新读，所以这一步只是"腾地方"，不丢数据。
    public func releaseIcons() {
        URLCache.shared.removeAllCachedResponses()
        log("已释放资源图标内存缓存")
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: cacheFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.shared.encode(cacheMap)
        try data.write(to: cacheFileURL)
    }
    
    
    private func url(of globalHash: String) -> URL {
        return iconCacheDirectory.appending(path: "\(globalHash.prefix(2))/\(globalHash)")
    }
    
    private func globalHash(of path: String, with fileHash: String) -> String {
        return (fileHash + path).sha1
    }
}
