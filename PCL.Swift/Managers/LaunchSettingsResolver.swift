//
//  LaunchSettingsResolver.swift
//  PCL.Swift
//
//  把"实例级覆盖值"与"全局默认值"合并成一份最终生效的启动设置。
//
//  为什么需要单独一层：实例配置里的每个字段都是三态（nil = 跟随全局），
//  启动流程与设置界面都要按同一套规则解读它们。如果两边各写一遍 if-let，
//  很容易出现"界面显示跟随全局、启动却用了旧值"这种对不上的情况。
//

import Foundation
import Core

/// 一次启动最终生效的设置。所有字段都已解析成确定值。
struct ResolvedLaunchSettings {
    let windowTitle: String
    let windowType: GameWindowType
    let windowWidth: Int
    let windowHeight: Int
    let launcherVisibility: LauncherVisibility
    let processPriority: ProcessPriority
    let prelaunchCommand: String
    let prelaunchWaitForCompletion: Bool
    let gameArguments: [String]
    let jvmArguments: [String]
    let memory: UInt64
    let memoryOptimize: Bool

    /// 合并实例覆盖值与全局默认值。
    /// - Parameters:
    ///   - config: 实例配置。
    ///   - global: 全局配置。
    static func resolve(instance config: MinecraftInstance.Config, global: LauncherConfig = .shared) -> ResolvedLaunchSettings {
        // 实例上没写 JVM 参数时用全局的；写了就完全替换（不做拼接，
        // 否则用户没法"删掉"全局参数里的某一项）。
        let jvmArguments: [String] = config.jvmArguments.isEmpty
            ? global.jvmArguments.splitToArguments()
            : config.jvmArguments

        return .init(
            windowTitle: config.gameWindowTitle ?? global.gameWindowTitle,
            windowType: config.gameWindowType ?? global.gameWindowType,
            windowWidth: config.gameWindowWidth ?? global.gameWindowWidth,
            windowHeight: config.gameWindowHeight ?? global.gameWindowHeight,
            launcherVisibility: config.launcherVisibility ?? global.launcherVisibility,
            processPriority: config.processPriority ?? global.processPriority,
            prelaunchCommand: config.prelaunchCommand ?? global.prelaunchCommand,
            prelaunchWaitForCompletion: config.prelaunchWaitForCompletion ?? global.prelaunchWaitForCompletion,
            gameArguments: config.gameArguments ?? global.gameArguments.splitToArguments(),
            jvmArguments: jvmArguments,
            memory: config.jvmHeapSize,
            memoryOptimize: config.memoryOptimize ?? global.memoryOptimize
        )
    }
}

// MARK: - 启动前命令

enum PrelaunchCommand {
    /// 执行启动前命令。
    ///
    /// 走 `/bin/sh -c`：用户写的是 shell 片段（`&&`、管道、环境变量），
    /// 直接 split 成 argv 会把这些语法当普通字符。
    ///
    /// - Parameters:
    ///   - command: 待执行的命令。空白字符串直接返回。
    ///   - wait: 是否等待命令结束。
    ///   - outputHandler: 标准输出与标准错误的内容回调。
    /// - Throws: 命令以非零状态退出时抛出。
    static func run(
        _ command: String,
        wait: Bool,
        outputHandler: (@MainActor (String) -> Void)? = nil
    ) async throws {
        let trimmed: String = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let process: Process = .init()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", trimmed]

        let pipe: Pipe = .init()
        process.standardOutput = pipe
        process.standardError = pipe

        log("正在执行启动前命令：\(trimmed)")
        try process.run()

        let handle: FileHandle = pipe.fileHandleForReading
        let readingTask: Task<Void, Never> = Task.detached {
            while true {
                let data: Data = handle.availableData
                if data.isEmpty { break }
                guard let text = String(data: data, encoding: .utf8) else { continue }
                if let outputHandler {
                    await outputHandler(text)
                }
            }
        }

        if wait {
            process.waitUntilExit()
            await readingTask.value
            guard process.terminationStatus == 0 else {
                throw SimpleError("启动前命令以状态码 \(process.terminationStatus) 退出。")
            }
            log("启动前命令执行完成")
        } else {
            log("启动前命令已执行，不等待其结束")
        }
    }
}
