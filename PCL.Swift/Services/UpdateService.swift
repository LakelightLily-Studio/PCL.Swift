//
//  UpdateService.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/26.
//

import SwiftUI
import Core

class UpdateService {
    public static let shared: UpdateService = .init()
    
    private let semaphore: AsyncSemaphore = .init(value: 1)
    
    public func runInteractiveUpdateFlow(manually: Bool = false) {
        if LauncherConfig.shared.ignoreLauncherUpdates && !manually {
            log("启动器更新被忽略，取消更新检查")
            return
        }
        Task {
            await semaphore.wait()
            defer { Task { await semaphore.signal() } }
            if manually {
                hint("正在检查更新……")
            }
            let version: UpdateInfo?
            do {
                version = try await UpdateManager.shared.checkUpdates()
            } catch {
                err("检查更新失败：\(error.localizedDescription)")
                if manually {
                    hint("检查更新失败：\(error.localizedDescription)", type: .critical)
                }
                return
            }
            guard let version else {
                if manually {
                    hint("当前使用的是最新版本，无需更新！", type: .finish)
                }
                return
            }
            
            let result = await MessageBoxManager.shared.showTextAsync(
                title: "PCL.Swift 有更新可用",
                content: "发现新版本：\(version.name)\n更新摘要：\(version.summary)\n\n是否下载并安装更新？",
                level: .info,
                buttons: version.updateLogLinks.enumerated().map { index, link in
                    return .init(id: index + 10, label: link.name, type: .normal) {
                        NSWorkspace.shared.open(link.url)
                    }
                } + [.init(id: 2, label: "不再提示", type: .normal), .no(), .yes(label: "下载并安装（\(ByteFormat.string(.init(version.downloads.size)))）", type: .highlight)]
            )
            
            if result == 2 {
                LauncherConfig.shared.ignoreLauncherUpdates = true
                return
            }
            
            if result != 1 {
                if !manually {
                    hint("你也可以在设置中手动更新！")
                }
                return
            }
            
            hint("正在从 GitHub 下载更新，完成后 PCL.Swift 会自动重启……")
            do {
                // 更新渠道只有 GitHub 一处，没有镜像可选（旧渠道的 useMirror 参数已删除）。
                try await UpdateManager.shared.installUpdate(version)
            } catch {
                err("更新启动器失败：\(error.localizedDescription)")
                hint("更新失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }
}
