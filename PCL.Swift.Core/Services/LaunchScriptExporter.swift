//
//  LaunchScriptExporter.swift
//  PCL.Swift.Core
//
//  把一次启动展开成可直接执行的启动脚本。
//
//  用途：用户想在终端里复现启动器的启动、或者把启动过程接进自己的脚本。
//  所以这里不生成"调用启动器"的脚本，而是把 JVM 与游戏参数原样展开——
//  否则换个环境就跑不起来。
//

import Foundation

public enum LaunchScriptExporter {
    /// 生成启动脚本。
    ///
    /// - Parameters:
    ///   - launcher: 已经配好参数的启动器实例。
    ///   - instanceName: 实例名，只用于脚本注释。
    /// - Returns: 可执行的 shell 脚本内容。
    ///
    /// 注意：脚本里的 accessToken 会被替换成占位符，避免把凭据写进文件。
    /// 用户需要自己填入有效 token，这一点会写在脚本注释里。
    public static func makeScript(launcher: MinecraftLauncher, instanceName: String) -> String {
        let options: LaunchOptions = launcher.options
        let arguments: [String] = buildArguments(launcher: launcher)

        var lines: [String] = []
        lines.append("#!/bin/sh")
        lines.append("# 由 PCL.Swift 导出的启动脚本")
        lines.append("# 实例：" + instanceName)
        lines.append("# 生成时间：" + ISO8601DateFormatter().string(from: .now))
        lines.append("#")
        lines.append("# 注意：下方的 accessToken 已被替换为占位符。")
        lines.append("# 直接运行本脚本会以离线身份进入游戏；要联机需自行填入有效令牌。")
        lines.append("")
        lines.append("cd " + shellEscape(options.runningDirectory.path) + " || exit 1")
        lines.append("")
        lines.append(shellEscape(options.javaRuntime.executableURL.path) + " \\")
        for (index, argument) in arguments.enumerated() {
            let escaped: String = shellEscape(argument)
            let isLast: Bool = index == arguments.count - 1
            lines.append("  " + escaped + (isLast ? "" : " \\"))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 展开完整的命令行参数（JVM + 主类 + 游戏参数）。
    ///
    /// 与 MinecraftLauncher.launch() 保持同构：那边把参数直接塞进 Process，
    /// 这边输出成数组供脚本使用。两处若不一致，导出的脚本就跑不起来，
    /// 所以这里复用同一套占位符替换规则。
    private static func buildArguments(launcher: MinecraftLauncher) -> [String] {
        let options: LaunchOptions = launcher.options
        let manifest: ClientManifest = options.manifest
        let runningDirectory: URL = options.runningDirectory
        let librariesURL: URL = options.repository.librariesDirectory

        var values: [String: String] = [
            "natives_directory": runningDirectory.appending(path: "natives").path,
            "launcher_name": "PCL.Swift",
            "launcher_version": Metadata.appVersion,
            "classpath_separator": ":",
            "library_directory": librariesURL.path,
            "auth_player_name": options.profile.name,
            "version_name": runningDirectory.lastPathComponent,
            "game_directory": runningDirectory.path,
            "assets_root": librariesURL.deletingLastPathComponent().appending(path: "assets").path,
            "assets_index_name": manifest.assetIndex?.id ?? manifest.assets ?? "legacy",
            "auth_uuid": UUIDUtils.string(of: options.profile.id, withHyphens: false),
            "auth_access_token": "<在此填入 accessToken>",
            "auth_session": "<在此填入 accessToken>",
            "user_type": "msa",
            "version_type": "PCL.Swift",
            "user_properties": "{}"
        ]
        values["classpath"] = buildClasspath(manifest: manifest, runningDirectory: runningDirectory, librariesURL: librariesURL)

        var arguments: [String] = []
        arguments.append("-Xmx" + String(options.memory) + "m")
        arguments.append(contentsOf: manifest.jvmArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(contentsOf: options.extraJvmArguments)
        if let authlibInjectorPath = options.authlibInjectorPath,
           let authServerURL = options.authServerURL,
           let prefetchedMeta = options.prefetchedMeta {
            arguments.append("-javaagent:" + authlibInjectorPath + "=" + authServerURL.absoluteString)
            arguments.append("-Dauthlibinjector.yggdrasil.prefetched=" + prefetchedMeta)
        }
        arguments.append(options.mainClass)
        arguments.append(contentsOf: manifest.gameArguments.flatMap { $0.rules.allSatisfy { $0.test(with: options) } ? $0.value : [] })
        arguments.append(contentsOf: options.extraGameArguments)

        return arguments.map { $0.replacingPlaceholders(with: values) }
    }

    private static func buildClasspath(manifest: ClientManifest, runningDirectory: URL, librariesURL: URL) -> String {
        var urls: [URL] = []
        for library in manifest.getLibraries() {
            if let artifact = library.artifact {
                urls.append(librariesURL.appending(path: artifact.path))
            }
        }
        urls.append(runningDirectory.appending(path: runningDirectory.lastPathComponent + ".jar"))
        return urls.map(\.path).joined(separator: ":")
    }

    /// 单引号包裹并转义内部的单引号，避免路径里的空格与特殊字符破坏脚本。
    private static func shellEscape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let escaped: String = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'" + escaped + "'"
    }
}
