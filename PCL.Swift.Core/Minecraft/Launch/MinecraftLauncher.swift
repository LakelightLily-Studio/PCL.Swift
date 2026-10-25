//
//  MinecraftLauncher.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/26.
//

import Foundation

public class MinecraftLauncher {
    private static let gameLogQueue: DispatchQueue = .init(label: "PCL.Mac.GameLog")
    public let options: LaunchOptions
    public let logURL: URL
    private let manifest: ClientManifest
    private let runningDirectory: URL
    private let librariesURL: URL
    private var values: [String: String]

    public init(options: LaunchOptions) {
        self.manifest = options.manifest
        self.runningDirectory = options.runningDirectory
        self.librariesURL = options.repository.librariesDirectory
        self.options = options
        self.logURL = URLConstants.tempURL.appending(path: "game-log-\(UUID().uuidString.lowercased()).log")
        let gameDirectory: URL = options.gameDirectory ?? options.runningDirectory
        self.values = [
            "natives_directory": runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Swift",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": librariesURL.path,

            "auth_player_name": options.profile.name,
            "version_name": options.runningDirectory.lastPathComponent,
            "game_directory": gameDirectory.path,
            "assets_root": librariesURL.deletingLastPathComponent().appending(path: "assets").path,
            "assets_index_name": manifest.assetIndex?.id ?? manifest.assets ?? "legacy",
            "auth_uuid": UUIDUtils.string(of: options.profile.id, withHyphens: false),
            "auth_access_token": options.accessToken,
            "auth_session": options.accessToken,
            "user_type": "msa",
            "version_type": "PCL.Swift",
            "user_properties": "{}"
        ]
    }

    /// 真正的工作目录：关闭版本隔离时是仓库根目录，否则就是实例目录。
    private var gameDirectoryURL: URL { options.gameDirectory ?? runningDirectory }

    /// 启动 Minecraft。
    /// - Returns: 游戏进程。
    public func launch() throws -> Process {
        values["classpath"] = buildClasspath()
        let process: Process = .init()
        process.executableURL = options.javaRuntime.executableURL
        process.currentDirectoryURL = gameDirectoryURL

        var arguments: [String] = []
        arguments.append("-Xmx\(options.memory)m")
        arguments.append(contentsOf: manifest.jvmArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(contentsOf: options.extraJvmArguments)
        arguments = applyGarbageCollector(to: arguments)
        if let authlibInjectorPath = options.authlibInjectorPath,
           let authServerURL = options.authServerURL,
           let prefetchedMeta = options.prefetchedMeta {
            arguments.append("-javaagent:\(authlibInjectorPath)=\(authServerURL)")
            arguments.append("-Dauthlibinjector.yggdrasil.prefetched=\(prefetchedMeta)")
            log("已添加 Authlib Injector 参数")
        }
        arguments.append(options.mainClass)

        var gameArguments: [String] = manifest.gameArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] }
        gameArguments.append(contentsOf: options.extraGameArguments)
        gameArguments = applyWindowArguments(to: gameArguments)
        arguments.append(contentsOf: gameArguments)

        arguments = arguments.map { $0.replacingPlaceholders(with: values) }
        process.arguments = arguments

        let pipe: Pipe = .init()
        process.standardOutput = pipe
        process.standardError = pipe

        log("正在使用以下参数启动 Minecraft：\(arguments.map { $0 == options.accessToken ? "🥚" : $0 })")
        applyQualityOfService(to: process)
        try process.run()

        applyProcessPriority(to: process)

        Self.gameLogQueue.async {
            FileManager.default.createFile(atPath: self.logURL.path, contents: nil)
            let handle: FileHandle?
            do {
                handle = try .init(forWritingTo: self.logURL)
            } catch {
                err("开启日志 FileHandle 失败：\(error.localizedDescription)")
                handle = nil
            }
            defer { try? handle?.close() }

            while process.isRunning {
                let data: Data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                try? handle?.write(contentsOf: data)
            }
        }
        return process
    }

    /// 按窗口设置覆盖清单里的窗口参数。
    ///
    /// 必须在"清单参数已展开"之后做：清单自己就带 `--width` / `--height`，
    /// 直接追加会出现两套同名参数，实测游戏会两套都不认，退回默认窗口。
    /// 所以这里先把已有的同名参数剔除，再按设置补一套。
    private func applyWindowArguments(to arguments: [String]) -> [String] {
        let managedFlags: Set<String> = ["--width", "--height", "--fullscreen"]
        var result: [String] = []
        var index: Int = 0
        while index < arguments.count {
            let argument: String = arguments[index]
            let flag: String = argument.contains("=") ? String(argument.split(separator: "=")[0]) : argument
            if managedFlags.contains(flag) {
                // `--width 854` 形式要连值一起跳过；`--width=854` 只有一项。
                if !argument.contains("=") && flag != "--fullscreen" {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            result.append(argument)
            index += 1
        }

        switch options.windowType {
        case .standard:
            // 不传窗口参数，交给游戏按自己的默认值开窗。
            break
        case .fullscreen:
            result.append("--fullscreen")
        case .custom:
            let width: Int = max(100, options.windowWidth)
            let height: Int = max(100, options.windowHeight)
            result.append("--width")
            result.append(String(width))
            result.append("--height")
            result.append(String(height))
        }
        return result
    }

    /// 按「内存管理」的设置替换 JVM 参数里的 GC 相关项。
    ///
    /// 先剔除再追加，而不是直接 append：
    /// - 清单（1.13+ 的官方 JSON）本身就带 `-XX:+UseG1GC` 和一堆 G1 调参；
    /// - 用户也可能在「额外 JVM 参数」里写了 GC 开关；
    /// - JVM 对同名开关按「最后一次出现生效」，两套并存时用户的选择可能被覆盖，
    ///   而 G1 的调参跑到 ZGC 命令行上纯属噪音。
    ///
    /// 选择「不指定」时什么都不做，完全尊重用户自己的参数。
    private func applyGarbageCollector(to arguments: [String]) -> [String] {
        guard options.garbageCollector != .unspecified else { return arguments }
        var result: [String] = GarbageCollectorArguments.removingManagedArguments(from: arguments)
        result.append(contentsOf: GarbageCollectorArguments.arguments(
            for: options.garbageCollector,
            javaMajorVersion: options.javaMajorVersion
        ))
        log("GC 设置：\(options.garbageCollector.description)，Java \(options.javaMajorVersion)，最终使用 \(options.garbageCollector.resolved(isG1GCUsing: options.javaMajorVersion) ? "G1GC" : "ZGC")")
        return result
    }

    /// 在 `run()` 之前设置调度等级（QoS）。
    ///
    /// Darwin 上 `Process` 没有 `priorityClass`（那是 Linux 的 Foundation），
    /// 而不提权的提优先级只能走 Quality of Service：内核按它决定线程的调度
    /// 权重与 P/E 核偏好，比 niceness 更贴近"游戏该不该抢 CPU"。
    /// 必须在启动前设置——进程跑起来之后，Java 自己创建的线程会按默认 QoS 生成，
    /// 再改进程的 QoS 对已有线程没有追溯效果。
    private func applyQualityOfService(to process: Process) {
        process.qualityOfService = switch options.processPriority {
        case .high: .userInteractive
        case .normal: .default
        case .low: .utility
        }
    }

    /// 在 `run()` 之后按 pid 调整 niceness。
    ///
    /// niceness 越小优先级越高，但**调高优先级（负值）需要 root**：普通用户对
    /// 子进程调 `setpriority(-5)` 必然拿到 EPERM。所以「高」实际靠上面的 QoS
    /// 生效，这里只是尽力而为；「低」是把 niceness 调大，任何用户都能做，两条路
    /// 都生效。
    ///
    /// 失败只记日志：优先级只影响调度手感，不值得让游戏启动失败。
    private func applyProcessPriority(to process: Process) {
        let niceness: Int32
        switch options.processPriority {
        case .high: niceness = -5
        case .normal: return
        case .low: niceness = 10
        }
        let pid: id_t = id_t(process.processIdentifier)
        guard setpriority(0, pid, niceness) == 0 else {
            let code: Int32 = errno
            if code == EPERM {
                warn("提高游戏进程优先级需要 root（EPERM），已退回 QoS 调度等级")
            } else {
                warn("设置游戏进程优先级失败：setpriority 返回 errno \(code)")
            }
            return
        }
        // 回读一次：setpriority 可能被系统夹紧，日志里要写实际生效值。
        let actual: Int32 = getpriority(0, pid)
        log("已将游戏进程优先级设为 \(options.processPriority.description)（niceness \(actual)）")
    }

    private func buildClasspath() -> String {
        var urls: [URL] = []
        for library in manifest.getLibraries() {
            if let artifact = library.artifact {
                urls.append(librariesURL.appending(path: artifact.path))
            }
        }
        urls.append(runningDirectory.appending(path: "\(runningDirectory.lastPathComponent).jar"))
        return urls.map(\.path).joined(separator: ":")
    }
}
