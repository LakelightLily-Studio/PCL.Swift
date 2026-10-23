//
//  InstanceListPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/29.
//

import SwiftUI
import Core

struct InstanceListPage: View {
    @StateObject private var viewModel: InstanceListViewModel
    @StateObject private var instanceVM: InstanceViewModel
    private let repositoryId: UUID
    
    init(instanceManager: InstanceManager, repositoryId: UUID) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, repositoryId: repositoryId))
        self._instanceVM = .init(wrappedValue: .init(instanceManager: instanceManager))
        self.repositoryId = repositoryId
    }
    
    var body: some View {
        CardContainer {
            MyCard("当前目录：\(viewModel.repository.name)", foldable: false) {
                infoLine(label: "路径") { MyText(viewModel.repository.url.path).textSelection(.enabled) }
                    .padding(.top, 6)
                infoLine(label: "实例数") { MyText(viewModel.instanceCount?.description ?? "-") }
                HStack(spacing: 15) {
                    MyButton("打开文件夹") {
                        NSWorkspace.shared.open(viewModel.repository.url)
                    }
                    .frame(width: 150)
                    MyButton("更改显示名称") {
                        MessageBoxManager.shared.showInput(title: "输入新名称") { name in
                            guard let name, !name.isEmpty else { return }
                            viewModel.rename(to: name)
                            AppRouter.shared.setRoot(.launch)
                            AppRouter.shared.append(.instanceList(repositoryId: viewModel.repository.id))
                            hint("已将目录名称更改为 \(name)！", type: .finish)
                        }
                    }
                    .frame(width: 150)
                    MyButton("移除目录", type: .red) {
                        MessageBoxManager.shared.showText(
                            title: "确认",
                            content: "你确定要移除这个目录（\(viewModel.repository.url.path)）吗？\n这只会把它从启动器的目录列表中移除，而不会删除任何文件。",
                            level: .info,
                            .no(), .yes()
                        ) { button in
                            guard button == 1 else { return }
                            viewModel.removeRepository()
                            AppRouter.shared.removeLast()
                            hint("移除成功！", type: .finish)
                        }
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 35)
                .padding(.top, 6)
            }
            
            if viewModel.loading {
                MyLoading(viewModel: viewModel.loadingViewModel)
            }
            
            if let errorInstances = viewModel.errorInstances, !errorInstances.isEmpty {
                MyCard("错误的实例") {
                    VStack(spacing: 0) {
                        ForEach(errorInstances, id: \.name) { instance in
                            MyListItem(.init(image: .iconRedstoneBlock, name: instance.name, description: instance.message))
                        }
                    }
                }
            }
            
            if let moddedInstances = viewModel.moddedInstances, !moddedInstances.isEmpty {
                MyCard("可安装 Mod", folded: viewModel.vanillaInstances?.isEmpty == false) {
                    instanceList(moddedInstances)
                }
                .cardIndex(1)
            }
            
            if let vanillaInstances = viewModel.vanillaInstances, !vanillaInstances.isEmpty {
                MyCard("常规实例", folded: false) {
                    instanceList(vanillaInstances)
                }
                .cardIndex(2)
            }
        }
        .onAppear {
            instanceVM.switchRepository(to: viewModel.repository)
        }
    }
    
    @ViewBuilder
    private func instanceList(_ instances: [MinecraftInstance]) -> some View {
        VStack(spacing: 0) {
            ForEach(instances, id: \.name) { instance in
                InstanceView(instance: instance)
                    .onTapGesture {
                        instanceVM.switchInstance(to: instance, in: viewModel.repository)
                        AppRouter.shared.removeLast()
                    }
            }
        }
    }
    
    @ViewBuilder
    private func infoLine(label: String,  @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, verticalPadding: 1, content: body)
    }
}

private struct InstanceView: View {
    /// 直接观察实例：改图标、改名、改收藏后这里会自动刷新。
    @ObservedObject private var instance: MinecraftInstance

    init(instance: MinecraftInstance) {
        self.instance = instance
    }

    var body: some View {
        MyListItem { _ in
            HStack(spacing: 0) {
                InstanceIconView(icon: instance.icon)
                    .frame(width: 36, height: 36)
                    .padding(.trailing, 6)

                VStack(alignment: .leading, spacing: 2) {
                    MyText(instance.title)
                        .lineLimit(1)
                    MyText(description, color: .colorGray3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 描述优先用用户填的，其次退回"版本 + 加载器 + 分类"。
    private var description: String {
        var parts: [String] = [instance.version.id]
        if let loader = instance.modLoader { parts.append(loader.description) }
        if let category = instance.category, !category.isEmpty { parts.append("分类：\(category)") }
        if let custom = instance.customDescription, !custom.isEmpty { parts.append(custom) }
        return parts.joined(separator: " · ")
    }
}

/// 统一的实例图标渲染。所有显示实例图标的地方都用它，避免各写一份分支。
struct InstanceIconView: View {
    let icon: InstanceIcon

    var body: some View {
        switch icon {
        case .custom(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        case .loader(let loader):
            Image(loader.icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.color1)
        case .fallback:
            Image(.iconGrassBlock)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.color1)
        }
    }
}
