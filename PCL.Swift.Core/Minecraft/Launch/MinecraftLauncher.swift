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
        self.values = [
            "natives_directory": runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Swift",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": librariesURL.path,

            "auth_player_name": options.profile.name,
            "version_name": options.runningDirectory.lastPathComponent,
            "game_directory": runningDirectory.path,
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

    /// 启动 Minecraft。
    /// - Returns: 游戏进程。
    public func launch() throws -> Process {
        values["classpath"] = buildClasspath()
        let process: Process = .init()
        process.executableURL = options.javaRuntime.executableURL
        process.currentDirectoryURL = runningDirectory

        var arguments: [String] = []
        arguments.append("-Xmx\(options.memory)m")
        arguments.append(contentsOf: manifest.jvmArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(contentsOf: options.extraJvmArguments)
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

    /// 按设置调整游戏进程优先级。
    ///
    /// Darwin 上 `Process` 没有 `priorityClass`（那是 Foundation on Linux 的东西），
    /// 只能直接调 POSIX 的 `setpriority`：niceness 越小优先级越高。
    /// 高优先级用 -5（普通用户能设的下限是 -20，但再往下会被系统拒），
    /// 低优先级用 15。
    ///
    /// 失败只记日志：优先级是锦上添花，权限不足时游戏仍应正常跑。
    private func applyProcessPriority(to process: Process) {
        let niceness: Int32
        switch options.processPriority {
        case .high: niceness = -5
        case .normal: return
        case .low: niceness = 15
        }
        let pid: id_t = id_t(process.processIdentifier)
        guard setpriority(0, pid, niceness) == 0 else {
            warn("设置游戏进程优先级失败：setpriority 返回 errno \(errno)")
            return
        }
        log("已将游戏进程优先级设为 \(options.processPriority.description)")
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
