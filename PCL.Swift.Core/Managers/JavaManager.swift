//
//  JavaManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import Foundation

public final class JavaManager: ObservableObject {
    private static var _shared: JavaManager?

    /// 全局实例。必须在启动阶段由 `AppDelegate` 注入后才能访问：
    /// 早于注入访问会立刻在注入点给出可定位的失败，而不是在某个随机调用点崩溃。
    public static var shared: JavaManager {
        guard let instance = _shared else {
            fatalError("JavaManager.shared 在注入之前被访问，请检查 AppDelegate 的初始化顺序。")
        }
        return instance
    }

    public static func install(_ instance: JavaManager) {
        _shared = instance
    }
    
    @Published public private(set) var javaRuntimes: [JavaRuntime]
    private var customJavaRuntimes: [URL]
    
    @MainActor
    public func research() throws {
        self.javaRuntimes = try JavaSearcher.search(customJavaRuntimes: customJavaRuntimes)
    }
    
    public init(customJavaRuntimes: [URL]) {
        self.customJavaRuntimes = customJavaRuntimes
        do {
            self.javaRuntimes = try JavaSearcher.search(customJavaRuntimes: customJavaRuntimes)
            log("Java 搜索完成，共 \(javaRuntimes.count) 个：")
            for javaRuntime in javaRuntimes {
                let type: String = .init(describing: javaRuntime.type).padding(toLength: 4, withPad: " ", startingAt: 0)
                let version: String = .init(describing: javaRuntime.version).padding(toLength: 10, withPad: " ", startingAt: 0)
                let arch: String = .init(describing: javaRuntime.architecture).padding(toLength: 8, withPad: " ", startingAt: 0)
                let impl: String = (javaRuntime.implementor ?? "").padding(toLength: 24, withPad: " ", startingAt: 0)
                log("\(type) \(version)\t\(arch)\t\(impl)\t\(javaRuntime.executableURL.path)")
            }
        } catch {
            err("搜索 Java 失败：\(error.localizedDescription)")
            self.javaRuntimes = []
        }
    }
    
    @MainActor
    public func addCustomRuntime(_ runtime: JavaRuntime) -> Bool {
        if javaRuntimes.contains(runtime) { return false }
        javaRuntimes.append(runtime)
        customJavaRuntimes.append(runtime.executableURL)
        return true
    }
    
    @MainActor
    @discardableResult
    public func removeCustomRuntime(_ executableURL: URL) -> Bool {
        guard let index = javaRuntimes.firstIndex(where: { $0.executableURL == executableURL }) else {
            return false
        }
        javaRuntimes.remove(at: index)
        customJavaRuntimes.removeAll(where: { $0 == executableURL })
        return true
    }
}
