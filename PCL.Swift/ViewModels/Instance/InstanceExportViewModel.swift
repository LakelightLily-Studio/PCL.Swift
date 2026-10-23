//
//  InstanceExportViewModel.swift
//  PCL.Swift
//

import Foundation
import AppKit
import Core

@MainActor
class InstanceExportViewModel: ObservableObject {
    @Published public var packName: String
    @Published public var packVersion: String = "1.0.0"
    @Published public var includeUnrecognizedFiles: Bool = true
    @Published public var includeLauncherConfig: Bool = false

    private let instance: MinecraftInstance
    private let repository: MinecraftRepository

    init(instanceManager: InstanceManager, id: String) {
        self.repository = instanceManager.currentRepository
        let instance: MinecraftInstance = instanceManager.currentRepository.instance(named: id)!
        self.instance = instance
        self.packName = instance.title
    }

    // MARK: - 整合包

    func exportModpack() {
        let name: String = packName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            hint("整合包名称不能为空！", type: .critical)
            return
        }
        let panel: NSSavePanel = .init()
        panel.title = "选择整合包保存位置"
        panel.nameFieldStringValue = name + ".mrpack"
        panel.allowedContentTypes = [.init(filenameExtension: "mrpack") ?? .zip]
        panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            self.runExport(to: url, name: name)
        }
    }

    private func runExport(to url: URL, name: String) {
        let options: ModpackExportService.Options = .init(
            name: name,
            version: packVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            includeUnrecognizedFiles: includeUnrecognizedFiles,
            includeLauncherConfig: includeLauncherConfig
        )
        let service: ModpackExportService = .init(instance: instance)
        let task: MyTask<EmptyModel> = .init(
            name: "导出整合包 - " + name,
            model: EmptyModel(),
            .init(0, "正在导出整合包") { task, _ in
                try await service.export(options: options, to: url) { progress in
                    task.setProgress(progress)
                }
                await MainActor.run {
                    hint("整合包导出完成！", type: .finish)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        )
        TaskManager.shared.execute(task: task)
        AppRouter.shared.append(.tasks)
    }

    // MARK: - 启动脚本

    func exportScript() {
        let panel: NSSavePanel = .init()
        panel.title = "选择脚本保存位置"
        panel.nameFieldStringValue = instance.name + ".sh"
        panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            self.runScriptExport(to: url)
        }
    }

    private func runScriptExport(to url: URL) {
        // 复用启动任务里那套参数装配逻辑：只有先把 options 填满，
        // 导出的脚本才与真实启动一致。
        // 用当前账号而不是"第一个账号"：脚本里的 auth_player_name 与 UUID
        // 来自这里，取错账号会导出一个身份不对的脚本。
        let accountId: UUID? = LauncherConfig.shared.currentAccountId
        let account: Account? = LauncherConfig.shared.accounts.first { $0.id == accountId }
            ?? LauncherConfig.shared.accounts.first
        guard let account else {
            hint("请先添加一个账号！", type: .critical)
            return
        }
        let settings: ResolvedLaunchSettings = .resolve(instance: instance.config)
        var options: LaunchOptions = .init()
        options.profile = account.profile
        options.accessToken = account.accessToken
        options.runningDirectory = instance.url
        options.repository = repository
        options.manifest = instance.manifest
        options.mainClass = instance.manifest.mainClass
        options.memory = settings.memory
        options.extraJvmArguments = settings.jvmArguments
        options.extraGameArguments = settings.gameArguments
        options.windowType = settings.windowType
        options.windowWidth = settings.windowWidth
        options.windowHeight = settings.windowHeight

        guard let java = JavaSearcher.pick(for: instance) else {
            hint("没有找到可用的 Java，无法导出启动脚本！", type: .critical)
            return
        }
        options.javaRuntime = java

        do {
            try options.validate()
        } catch {
            hint("导出启动脚本失败：" + error.localizedDescription, type: .critical)
            return
        }

        let launcher: MinecraftLauncher = .init(options: options)
        let script: String = LaunchScriptExporter.makeScript(launcher: launcher, instanceName: instance.name)
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            hint("启动脚本导出完成！", type: .finish)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            err("写入启动脚本失败：" + error.localizedDescription)
            hint("写入启动脚本失败：" + error.localizedDescription, type: .critical)
        }
    }
}
