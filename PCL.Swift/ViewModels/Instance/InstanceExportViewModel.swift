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
        panel.presentAsSheet { [weak self] result in
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

}