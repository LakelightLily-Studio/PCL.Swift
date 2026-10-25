//
//  ModpackViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/23.
//

import Foundation
import Core

class ModpackViewModel: ObservableObject {
    private let instanceManager: InstanceManager
    
    init(instanceManager: InstanceManager) {
        self.instanceManager = instanceManager
    }
    
    @MainActor
    public func importModpack(at url: URL, repository: MinecraftRepository) async {
        // CurseForge API Key 只对 CurseForge 格式的整合包是必需的。
        //
        // 原先这里无条件 guard，导致没有配置 Key 的构建连 Modrinth / .mrpack /
        // 普通压缩包都导不进来（Issue #2：不能导入整合包）。现在把「有没有 Key」
        // 交给服务层判断：只有真的碰到 manifest.json（CurseForge 格式）时才报错。
        //
        // Issue #4：没有 Key 时不能拿空字符串造客户端再让请求 401 回来，
        // 那样用户看到的错误与真正原因无关。Secrets 只在真有 Key 时给出客户端。
        let service = ModpackImportService(curseforgeClient: Secrets.shared.curseforgeClient, modpackURL: url)
        
        let handleUnknownError: (Error) -> Void = { (error: Error) in
            MessageBoxManager.shared.showText(
                title: "发生未知错误",
                content: "\(error.localizedDescription)\n\n若要寻求帮助，请将完整日志报告发送给他人，而不是发送关于此页面的图片。",
                level: .error
            )
        }
        
        do {
            let index = try service.load()
            guard await MessageBoxManager.shared.showTextAsync(
                title: "整合包信息",
                content: "格式：\(index.format)\n名称：\(index.name)\n版本：\(index.version)\n作者：\(index.author ?? "未知")\n描述：\(index.description ?? "空")\n依赖：\(index.dependencyInfo)\n\n是否继续安装？",
                level: .info,
                .no(),
                .yes(label: "继续")
            ) == 1 else { return }
            
            guard let name = await MessageBoxManager.shared.showInputAsync(
                title: "导入整合包 - 输入实例名",
                initialContent: index.name
            ) else { return }
            
            
            let completion: @MainActor (MinecraftInstance) -> Void = { instance in
                self.instanceManager.switchInstance(to: instance, in: repository)
            }
            
            if index.format == .simple {
                let task = try service.createSimpleImportTask(name: name, repository: repository, completion: completion)
                TaskManager.shared.execute(task: task)
            } else {
                let task = try service.createImportTask(name: name, repository: repository, completion: completion)
                TaskManager.shared.execute(task: task)
            }
            
            AppRouter.shared.append(.tasks)
        } catch let error as ModpackImportService.LoadError {
            switch error {
            case .extractFailed(_):
                MessageBoxManager.shared.showText(
                    title: "解压整合包失败",
                    content: "\(error.localizedDescription)",
                    level: .error
                )
            case .unsupportedModLoader(let name):
                MessageBoxManager.shared.showText(
                    title: "不支持的模组加载器",
                    content: "很抱歉，PCL.Swift 暂时不支持安装这个整合包使用的 \(name) 加载器……",
                    level: .error
                )
            case .missingCurseforgeClient:
                // 以前这里只说「从官方渠道重新下载」，用户没有任何可执行的动作
                // （Issue #4 的截图就是这条）。现在直接给一个能跳到设置页的按钮：
                // 手填的 Key 会立刻生效，不必重启，也不必等新版发布。
                MessageBoxManager.shared.showText(
                    title: "缺少 CurseForge API Key",
                    content: "这个整合包使用 CurseForge 格式（内含 manifest.json），解析它必须带 CurseForge API Key。\n\n请到 设置 → 其他 → 社区资源 填入自己的 Key（可在 CurseForge 官网免费申请），或设置环境变量 PCLMAC_CURSE_FORGE_API_KEY 后重启启动器。",
                    level: .error,
                    .no(),
                    .yes(label: "去设置", type: .highlight)
                ) { button in
                    guard button == 1 else { return }
                    // 直接把路由切到「设置 → 其他」：那里有可以手填 Key 的输入框。
                    let router: AppRouter = .shared
                    router.setRoot(.settings)
                    router.replaceLast(.launcherSettings)
                }
            case .unknownFormat:
                MessageBoxManager.shared.showText(
                    title: "不支持的整合包格式",
                    content: "很抱歉，PCL.Swift 目前只支持导入 Modrinth、CurseForge、MCBBS 和普通压缩包格式的整合包，不支持这个整合包使用的格式……",
                    level: .error
                )
            default:
                handleUnknownError(error)
            }
        } catch let error as ModpackImportService.ImportError {
            switch error {
            case .invalidName(let underlying):
                hint("该名称无效：\(underlying.localizedDescription)", type: .critical)
            case .extractFailed(_):
                MessageBoxManager.shared.showText(
                    title: "解压整合包失败",
                    content: "\(error.localizedDescription)",
                    level: .error
                )
            default:
                handleUnknownError(error)
            }
        } catch {
            // Swift 要求 catch 覆盖全部错误；走到这里的是上面两个类型化 catch 之外的错误，
            // 按未知错误处理，不再交给 handleUnknownError 是为了避免重复弹窗。
            err("导入整合包时出现未分类错误：\(error.localizedDescription)")
        }
    }
}
