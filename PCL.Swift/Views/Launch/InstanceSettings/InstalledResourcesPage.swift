//
//  InstalledResourcesPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/6/7.
//

import SwiftUI
import Core
import UniformTypeIdentifiers

struct InstalledResourcesPage: View {
    @StateObject private var viewModel: InstalledResourcesViewModel
    @StateObject private var loadingVM: MyLoadingViewModel

    init(instanceManager: InstanceManager, id: String, type: ResourceType) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id, type: type))
        self._loadingVM = .init(wrappedValue: MyLoadingViewModel(text: "加载中"))
    }

    var body: some View {
        Group {
            if !viewModel.supportMods {
                unsupportedCard
            } else {
                CardContainer {
                    if viewModel.type == .shader {
                        MyTip(text: "光影包需要搭配光影加载器使用。\n详细教程：https://cylorine.studio/helps/shader", theme: .blue)
                            .onTapGesture {
                                NSWorkspace.shared.open(URL(string: "https://cylorine.studio/helps/shader")!)
                            }
                    }
                    if viewModel.type == .datapack {
                        MyTip(text: "数据包安装在各个存档的 datapacks 目录下，需要先在「下载 → 数据包」里选存档安装。这里列出的是当前实例所有存档里的数据包。", theme: .yellow)
                    }

                    MySearchBox(placeholder: "搜索\(viewModel.type.localizedName)") { keyword in
                        viewModel.setSearchKeyword(keyword)
                    }

                    toolbarCard
                        .cardIndex(1)

                    if let resources = viewModel.resources, !resources.isEmpty {
                        PaginatedContainer(currentPage: $viewModel.currentPage, pageCount: viewModel.pageCount) { currentPage in
                            MyCard(nil) {
                                VStack(spacing: 0) {
                                    ForEach(resources, id: \.id) { resource in
                                        ResourceListItem(viewModel: viewModel, resource: resource)
                                    }
                                }
                            }
                            .onChange(of: currentPage) { _ in
                                viewModel.updateResources()
                            }
                        }
                    } else {
                        MyLoading(viewModel: loadingVM)
                    }
                }
            }
        }
        .task {
            loadingVM.reset()
            do {
                try await viewModel.load()
            } catch {
                err("加载资源列表失败：\(error.localizedDescription)")
                loadingVM.fail(with: "加载资源列表失败：\(error.localizedDescription)")
            }
        }
        .onChange(of: viewModel.resources) { newValue in
            if let newValue, newValue.isEmpty {
                if viewModel.hasSearchKeyword {
                    loadingVM.fail(with: "没有匹配的结果")
                } else if viewModel.filter != .all {
                    loadingVM.fail(with: "当前筛选条件下没有\(viewModel.type.localizedName)")
                } else {
                    loadingVM.fail(with: "这个实例没有安装任何\(viewModel.type.localizedName)！")
                }
            }
        }
        .onDisappear {
            viewModel.resources = nil
        }
    }

    // MARK: - 工具栏

    private var toolbarCard: some View {
        MyCard(nil) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    MyButton("打开文件夹") {
                        if let directory = viewModel.directory() {
                            NSWorkspace.shared.open(directory)
                        }
                    }
                    .frame(width: 110)
                    MyButton("从文件安装") { installFromFile() }
                        .frame(width: 110)
                    MyButton("下载\(viewModel.type.localizedName)") {
                        AppRouter.shared.setRoot(.download)
                        switch viewModel.type {
                        case .mod: AppRouter.shared.append(.modDownload)
                        case .resourcepack: AppRouter.shared.append(.resourcepackDownload)
                        case .shader: AppRouter.shared.append(.shaderpackDownload)
                        case .datapack: AppRouter.shared.append(.datapackDownload)
                        case .modpack: AppRouter.shared.append(.modpackDownload)
                        }
                    }
                    .frame(width: 130)
                    Spacer(minLength: 0)
                }
                .frame(height: 32)

                HStack(spacing: 12) {
                    MySelect($viewModel.filter, entries: InstalledResourcesViewModel.Filter.allCases)
                        .frame(width: 110)

                    MyButton("检测更新", disabled: viewModel.checkingUpdates) {
                        Task { await viewModel.checkUpdates() }
                    }
                    .frame(width: 90)

                    Divider()
                        .frame(height: 20)

                    MyButton(viewModel.selectedIds.isEmpty ? "全选" : "取消选择") {
                        if viewModel.selectedIds.isEmpty {
                            viewModel.selectAll()
                        } else {
                            viewModel.clearSelection()
                        }
                    }
                    .frame(width: 90)

                    MyButton("启用", disabled: viewModel.selectedIds.isEmpty) {
                        batchSetEnabled(true)
                    }
                    .frame(width: 60)
                    MyButton("禁用", disabled: viewModel.selectedIds.isEmpty) {
                        batchSetEnabled(false)
                    }
                    .frame(width: 60)
                    MyButton("删除", type: .red, disabled: viewModel.selectedIds.isEmpty) {
                        batchDelete()
                    }
                    .frame(width: 60)

                    Spacer(minLength: 0)

                    if !viewModel.selectedIds.isEmpty {
                        MyText("已选择 \(viewModel.selectedIds.count) 个文件", size: 12, color: .colorGray3)
                    }
                }
                .frame(height: 32)
            }
            .padding(2)
        }
    }

    private var unsupportedCard: some View {
        MyCard(nil) {
            VStack(spacing: 10) {
                MyText("该实例不可使用 Mod", size: 19, color: .color3)

                Rectangle()
                    .fill(Color.color3)
                    .frame(height: 2)

                MyText("你需要先安装 Forge、Fabric 等 Mod 加载器才能使用 Mod，请在安装实例时选择这些加载器。\n如果你已经安装了 Mod 加载器，那么你很可能选择了错误的实例，请点击实例选择按钮切换实例。")
                    .padding(.vertical, 5)

                HStack(spacing: 20) {
                    MyButton("转到下载页面", type: .highlight) {
                        AppRouter.shared.setRoot(.download)
                    }
                    .frame(width: 140)
                    MyButton("实例选择") {
                        AppRouter.shared.setRoot(.launch)
                        AppRouter.shared.append(.instanceList(repositoryId: viewModel.currentRepositoryId))
                    }
                    .frame(width: 140)
                }
                .frame(height: 35)
            }
            .padding(10)
        }
        .padding(40)
    }

    // MARK: - 操作

    private func batchSetEnabled(_ enabled: Bool) {
        let targets: [ResourceDisplayModel] = viewModel.selectedResources
        guard !targets.isEmpty else { return }
        let count: Int = viewModel.setEnabled(enabled, for: targets)
        if count > 0 {
            hint("已\(enabled ? "启用" : "禁用") \(count) 个文件！", type: .finish)
        } else {
            hint("没有需要处理的文件。", type: .info)
        }
        viewModel.clearSelection()
        viewModel.updateResources()
    }

    private func batchDelete() {
        let targets: [ResourceDisplayModel] = viewModel.selectedResources
        guard !targets.isEmpty else { return }
        MessageBoxManager.shared.showText(
            title: "确认删除",
            content: "你确定要删除这 \(targets.count) 个文件吗？\n这个操作无法撤销！",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { button in
            guard button == 1 else { return }
            let count: Int = viewModel.delete(targets)
            hint("已删除 \(count) 个文件！", type: count > 0 ? .finish : .critical)
            viewModel.updateResources()
        }
    }

    private func installFromFile() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "jar") ?? .zip]
        panel.title = "选择要安装的\(viewModel.type.localizedName)"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            // 数据包要选存档：作用域是单个世界，选错了装进去也不会生效。
            if viewModel.type == .datapack {
                let saves: [String] = viewModel.availableSaves
                guard !saves.isEmpty else {
                    hint("这个实例还没有任何存档，请先进入游戏创建一个世界！", type: .critical)
                    return
                }
                MessageBoxManager.shared.showList(
                    title: "选择要安装到的存档",
                    items: saves.map { .init(name: $0, description: nil) }
                ) { index in
                    guard let index else { return }
                    self.performInstall(from: url, saveName: saves[index])
                }
                return
            }
            performInstall(from: url, saveName: nil)
        }
    }

    private func performInstall(from url: URL, saveName: String?) {
        do {
            try viewModel.install(from: url, saveName: saveName)
            hint("已安装 \(url.lastPathComponent)！", type: .finish)
            Task {
                try? await viewModel.load(resetPage: false)
            }
        } catch {
            err("从文件安装失败：\(error.localizedDescription)")
            hint("从文件安装失败：\(error.localizedDescription)", type: .critical)
        }
    }
}

private struct ResourceListItem: View {
    @ObservedObject private var viewModel: InstalledResourcesViewModel
    @ObservedObject private var resource: ResourceDisplayModel

    init(viewModel: InstalledResourcesViewModel, resource: ResourceDisplayModel) {
        self.viewModel = viewModel
        self.resource = resource
    }

    private var isSelected: Bool { viewModel.selectedIds.contains(resource.id) }

    var body: some View {
        MyListItem { hovered in
            HStack {
                // 复选框常驻：批量操作要求用户随时能看到"哪些被选中"，
                // 只在 hover 时出现会让跨页选择变成猜谜。
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15)
                    .foregroundStyle(isSelected ? Color.color3 : .colorGray4)
                    .contentShape(.rect)
                    .padding(.trailing, 6)
                    .onTapGesture { viewModel.toggleSelection(resource) }

                resource.icon.makeView()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.color1)

                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 0) {
                        Group {
                            if #available(macOS 13, *) {
                                MyText(resource.name)
                                    .strikethrough(resource.disabled)
                            } else {
                                MyText((resource.disabled ? "（已禁用）" : "") + resource.name)
                            }
                        }
                        .animation(.easeInOut(duration: 0.1), value: resource.disabled)

                        MyText(" | \(resource.fileName)", size: 12, color: .colorGray3)
                        HStack(spacing: 3) {
                            ForEach(resource.tags, id: \.self) { tag in
                                MyTag(tag, labelColor: .colorGray2, backgroundColor: .black.opacity(0.05), size: 12)
                            }
                        }
                        .padding(.leading, 3)

                        if viewModel.updatableURLs.contains(resource.url) {
                            MyTag("可更新", labelColor: .white, backgroundColor: .color3, size: 12)
                                .padding(.leading, 4)
                        }
                    }
                    HStack(spacing: 0) {
                        if let version = resource.version {
                            MyText("\(version) | ", size: 12, color: .colorGray3)
                        }
                        MyText(resource.description, size: 12, color: .colorGray3)
                    }
                }
                .lineLimit(1)
                .textSelection(.enabled)

                Spacer(minLength: 0)

                HStack {
                    ListItemButton(.resource(.btnOpen), scale: 0.8) {
                        NSWorkspace.shared.activateFileViewerSelecting([resource.url])
                    }
                    if !resource.sources.isEmpty {
                        ListItemButton(.resource(.iconAbout), clickPerform: viewInfo)
                    }
                    ListItemButton(.resource(resource.disabled ? .btnEnable : .btnDisable), clickPerform: toggleDisabled)
                        .animation(.easeInOut(duration: 0.1), value: resource.disabled)
                    ListItemButton(.system("trash"), clickPerform: deleteOne)
                }
                .padding(.horizontal, 4)
                .allowsHitTesting(hovered)
                .opacity(hovered ? 1 : 0)
            }
        }
        .onTapGesture {
            viewModel.toggleSelection(resource)
        }
    }

    private func viewInfo() {
        Task {
            do {
                guard let info = try await viewModel.loadInfo(for: resource) else {
                    hint("未找到 \(resource.fileName) 对应的远端资源信息！", type: .critical)
                    return
                }
                AppRouter.shared.append(.projectInstall(project: info))
            } catch {
                err("获取资源信息失败：\(error.localizedDescription)")
                hint("获取资源信息失败：\(error.localizedDescription)", type: .critical)
            }
        }
    }

    private func toggleDisabled() {
        do {
            try viewModel.toggleDisabled(resource)
        } catch {
            let type = resource.disabled ? "启用" : "禁用"
            err("\(type)资源失败：\(error.localizedDescription)")
            hint("\(type)资源失败：\(error.localizedDescription)", type: .critical)
        }
    }

    private func deleteOne() {
        MessageBoxManager.shared.showText(
            title: "确认删除",
            content: "你确定要删除 \(resource.fileName) 吗？\n这个操作无法撤销！",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { button in
            guard button == 1 else { return }
            let count: Int = viewModel.delete([resource])
            if count > 0 {
                hint("已删除 \(resource.fileName)！", type: .finish)
            }
            viewModel.updateResources()
        }
    }
}
