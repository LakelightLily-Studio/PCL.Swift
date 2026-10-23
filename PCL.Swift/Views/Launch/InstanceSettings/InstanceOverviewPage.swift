//
//  InstanceOverviewPage.swift
//  PCL.Swift
//
//  实例概览：图标、显示名、描述、收藏、分类，以及各子目录的快捷入口。
//
//  与原版 PCL 的「概览」页对应。这里只做"看一眼 + 改元数据 + 打开目录"，
//  真正的启动参数在「配置」页，资源在「Mod 管理」等页。
//

import SwiftUI
import Core
import UniformTypeIdentifiers

struct InstanceOverviewPage: View {
    @StateObject private var viewModel: InstanceOverviewViewModel

    init(instanceManager: InstanceManager, id: String) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id))
    }

    var body: some View {
        CardContainer {
            headerCard
            folderCard
                .cardIndex(1)
            actionCard
                .cardIndex(2)
        }
    }

    // MARK: - 头部

    private var headerCard: some View {
        MyCard(nil) {
            HStack(alignment: .top, spacing: 14) {
                iconView
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.colorGray5, lineWidth: 1)
                    }
                    .contentShape(.rect)
                    .onTapGesture { chooseIcon() }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MyText(viewModel.displayTitle, size: 18)
                            .lineLimit(1)
                        if viewModel.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.color3)
                        }
                        Spacer(minLength: 0)
                    }
                    MyText(viewModel.subtitle, size: 12, color: .colorGray3)
                        .lineLimit(1)
                    MyText(viewModel.descriptionText, size: 12, color: .colorGray2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .trailing, spacing: 8) {
                    MyButton(viewModel.isFavorite ? "取消收藏" : "加入收藏") {
                        viewModel.toggleFavorite()
                        hint(viewModel.isFavorite ? "已加入收藏夹！" : "已取消收藏！", type: .finish)
                    }
                    .frame(width: 100)
                    MyButton("更换图标") {
                        chooseIcon()
                    }
                    .frame(width: 100)
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let image = viewModel.iconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            Image(viewModel.fallbackIcon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.color1)
                .padding(6)
        }
    }

    // MARK: - 文件夹

    private var folderCard: some View {
        MyCard("文件夹", foldable: false) {
            VStack(spacing: 0) {
                ForEach(viewModel.folders, id: \.key) { folder in
                    MyListItem { hovered in
                        HStack {
                            Image(systemName: "folder")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18)
                                .foregroundStyle(hovered ? Color.color3 : .colorGray2)
                            VStack(alignment: .leading, spacing: 2) {
                                MyText(folder.title)
                                MyText(folder.relativePath, size: 12, color: .colorGray3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if !folder.exists {
                                MyTag("不存在", labelColor: .colorGray2, backgroundColor: .black.opacity(0.05), size: 12)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onTapGesture {
                        viewModel.open(folder)
                        // 打开时可能顺手建了目录，回来后刷新一次存在状态。
                        viewModel.refreshFolders()
                    }
                }
            }
        }
    }

    // MARK: - 操作

    private var actionCard: some View {
        MyCard("操作", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 15) {
                    MyButton("修改名称") { rename() }
                        .frame(width: 110)
                    MyButton("修改描述") { editDescription() }
                        .frame(width: 110)
                    MyButton("设置分类") { editCategory() }
                        .frame(width: 110)
                    Spacer()
                }
                .frame(height: 35)

                HStack(spacing: 15) {
                    MyButton("补全文件") {
                        viewModel.repair()
                    }
                    .frame(width: 110)
                    MyButton("导出启动脚本") {
                        AppRouter.shared.append(.instanceExport(id: viewModel.instanceName))
                    }
                    .frame(width: 130)
                    MyButton("导出整合包") {
                        AppRouter.shared.append(.instanceExport(id: viewModel.instanceName))
                    }
                    .frame(width: 110)
                    Spacer()
                }
                .frame(height: 35)

                MyTip(text: "补全会重新校验并补齐缺失的客户端、资源索引与依赖库。它不会删除你已经装的 Mod 与存档。", theme: .blue)
            }
        }
    }

    // MARK: - 交互

    private func chooseIcon() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.title = "选择实例图标"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            viewModel.setIcon(url)
        }
    }

    private func rename() {
        MessageBoxManager.shared.showInput(
            title: "输入新的显示名称",
            initialContent: viewModel.displayTitle,
            placeholder: "留空则使用文件夹名"
        ) { name in
            guard let name else { return }
            viewModel.setDisplayName(name)
            hint("名称已更新！", type: .finish)
        }
    }

    private func editDescription() {
        MessageBoxManager.shared.showInput(
            title: "输入实例描述",
            initialContent: viewModel.customDescriptionText,
            placeholder: "这个版本是做什么用的？"
        ) { text in
            guard let text else { return }
            viewModel.setDescription(text)
            hint("描述已更新！", type: .finish)
        }
    }

    private func editCategory() {
        MessageBoxManager.shared.showInput(
            title: "输入分类名称",
            initialContent: viewModel.category ?? "",
            placeholder: "例如：生存、科技、整合"
        ) { text in
            guard let text else { return }
            viewModel.setCategory(text)
            hint("分类已更新！", type: .finish)
        }
    }
}
