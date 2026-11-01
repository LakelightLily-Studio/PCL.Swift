//
//  InstanceListSidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/27.
//

import SwiftUI
import Core

struct InstanceListSidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 300

    @StateObject private var instanceVM: InstanceViewModel
    @StateObject private var modpackViewModel: ModpackViewModel
    
    init(instanceManager: InstanceManager) {
        self._instanceVM = .init(wrappedValue: InstanceViewModel(instanceManager: instanceManager))
        self._modpackViewModel = .init(wrappedValue: ModpackViewModel(instanceManager: instanceManager))
    }
    
    let width: CGFloat = 300

    /// 入场 / 退场错峰的控件总数：两个灰色小标题 + 目录条目。
    private var controlCount: Int {
        instanceVM.repositories.isEmpty ? 1 : instanceVM.repositories.count + 2
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !instanceVM.repositories.isEmpty {
                SidebarSectionTitle("目录列表", color: .colorGray3, index: 0, exitCount: controlCount)
                    .padding(.top, 18)
                MyNavigationList(
                    routeList: instanceVM.repositories.map {
                        .init(AppRoute.instanceList(repositoryId: $0.id), nil, $0.name)
                    },
                    indexOffset: 1,
                    exitCount: controlCount
                ) { route in
                    switch route {
                    case .instanceList(let repositoryId):
                        guard case .instanceList(let currentRepositoryId) = AppRouter.shared.last,
                              repositoryId == currentRepositoryId else { return }
                        instanceVM.reload(repository: instanceVM.currentRepository)
                    default:
                        return
                    }
                }
            }
            SidebarSectionTitle(
                "添加或导入",
                color: .colorGray3,
                index: instanceVM.repositories.isEmpty ? 0 : instanceVM.repositories.count + 1,
                exitCount: controlCount
            )
            .padding(.top, 18)
            VStack(spacing: 0) {
                ImportButton(.iconAdd, "添加已有目录", perform: requestAddRepository)
                ImportButton(.iconImportModpack, "导入整合包", perform: onImportModpackClicked)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func requestAddRepository() {
        let panel: NSOpenPanel = .init()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        // sheet 而不是 runModal：不要弹出一扇与启动器脱节的独立窗口。
        panel.presentAsSheet { result in
            guard result == .OK, let url = panel.url else { return }
            if let repository = instanceVM.repositories.first(where: { $0.url == url }) {
                instanceVM.switchRepository(to: repository)
                AppRouter.shared.setRoot(.launch)
                AppRouter.shared.append(.instanceList(repositoryId: repository.id))
                return
            }
            MessageBoxManager.shared.showInput(
                title: "输入目录名",
                initialContent: url.lastPathComponent
            ) { name in
                if let name {
                    instanceVM.addRepository(name: name, url: url)
                }
            }
        }
    }
    
    private func onImportModpackClicked() {
        let repository = instanceVM.currentRepository
        
        let panel: NSOpenPanel = .init()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .zip,
            .init(filenameExtension: "mrpack")!
        ]
        
        panel.presentAsSheet { result in
            guard result == .OK, let url = panel.url else { return }
            Task.detached {
                await modpackViewModel.importModpack(at: url, repository: repository)
            }
        }
    }
}

private struct ImportButton: View {
    private let icon: ImageResource
    private let label: String
    private let perform: () throws -> Void
    
    public init(_ icon: ImageResource, _ label: String, perform: @escaping () throws -> Void) {
        self.icon = icon
        self.label = label
        self.perform = perform
    }
    
    var body: some View {
        MyListItem {
            HStack {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22)
                    .foregroundStyle(Color.color1)
                    .padding(.leading, 10)
                MyText(label)
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .onTapGesture {
            try? perform()
        }
    }
}
