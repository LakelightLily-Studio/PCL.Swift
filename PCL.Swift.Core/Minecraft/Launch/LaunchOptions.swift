//
//  LaunchOptions.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/21.
//

import Foundation

public struct LaunchOptions {
    public var profile: PlayerProfile!
    public var accessToken: String!
    public var javaRuntime: JavaRuntime!
    public var runningDirectory: URL!
    public var manifest: ClientManifest!
    public var repository: MinecraftRepository!
    public var memory: UInt64 = 4096
    public var mainClass: String!
    public var extraJvmArguments: [String] = []
    public var demo: Bool = false

    // Authlib Injector
    public var authlibInjectorPath: String?
    public var authServerURL: URL?
    public var prefetchedMeta: String?

    // MARK: - 窗口与进程

    /// 窗口模式。
    public var windowType: GameWindowType = .standard
    /// 自定义窗口宽度。
    public var windowWidth: Int = 854
    /// 自定义窗口高度。
    public var windowHeight: Int = 480
    /// 游戏进程优先级。
    public var processPriority: ProcessPriority = .normal
    /// 游戏工作目录（存档、Mod、options.txt 都落在这里）。
    ///
    /// nil 表示就是实例目录本身（版本隔离）。关闭隔离时指向仓库根目录，
    /// 于是多个版本共用同一份存档与 Mod。
    public var gameDirectory: URL?
    /// 垃圾回收器策略。由它派生出的 JVM 参数会替换清单与自定义参数里的同类项。
    public var garbageCollector: GarbageCollectorMode = .tunedG1
    /// 本次启动所用 Java 的大版本号。GC 参数按它分档（ZGC 需要 15+，分代 ZGC 需要 21+）。
    public var javaMajorVersion: Int = 8

    /// 附加游戏参数，追加在清单参数之后。
    public var extraGameArguments: [String] = []

    public func validate() throws {
        if profile == nil || accessToken == nil { throw LaunchError.missingAccount }
        if javaRuntime == nil { throw LaunchError.missingJava }
        if runningDirectory == nil { throw LaunchError.missingRunningDirectory }
        if manifest == nil { throw LaunchError.missingManifest }
        if repository == nil { throw LaunchError.missingRepository }
        if mainClass == nil { throw LaunchError.missingMainClass}
    }

    public init() {}
}
