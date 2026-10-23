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

    /// 游戏窗口标题。nil 表示不指定，交给游戏自己。
    ///
    /// 注意这不改游戏内的窗口标题（那是 options.txt 的 levelname），
    /// 只影响窗口管理器里显示的名字，用于让启动器能认准这个进程的窗口。
    public var windowTitle: String?
    /// 窗口模式。
    public var windowType: GameWindowType = .standard
    /// 自定义窗口宽度。
    public var windowWidth: Int = 854
    /// 自定义窗口高度。
    public var windowHeight: Int = 480
    /// 游戏进程优先级。
    public var processPriority: ProcessPriority = .normal

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
