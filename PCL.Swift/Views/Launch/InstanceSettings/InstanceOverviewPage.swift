//
//  InstanceOverviewPage.swift
//  PCL.Swift
//
//  实例设置 → 概览。
//
//  卡片与行序对齐 PCL2 的 PageInstanceOverall：实例信息 / 个性化 / 快捷方式 / 高级管理。
//

import SwiftUI
import Core

struct InstanceOverviewPage: View {
    @StateObject private var viewModel: InstanceOverviewViewModel
    @State private var showingIconPicker: Bool = false

    init(instanceManager: InstanceManager, id: String) {
        self._viewModel = .init(wrappedValue: .init(instanceManager: instanceManager, id: id))
    }

    var body: some View {
        CardContainer {
            headerCard
            personalizationCard
                .cardIndex(1)
            shortcutCard
                .cardIndex(2)
            managementCard
                .cardIndex(3)
        }
        .sheet(isPresented: $showingIconPicker) {
            InstanceIconPicker(viewModel: viewModel)
        }
    }

    // MARK: - 实例信息

    private var headerCard: some View {
        MyCard(nil, padding: 10) {
            MyListItem { _ in
                HStack(spacing: 0) {
                    InstanceIconView(icon: icon)
                        .frame(width: 36, height: 36)
                        .padding(.trailing, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        MyText(viewModel.displayTitle)
                            .lineLimit(1)
                        MyText(viewModel.subtitle, color: .colorGray3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 图标视图的输入：自定义图片 > 加载器图标 > 兜底草方块。
    private var icon: InstanceIcon {
        if let image = viewModel.iconImage { return .custom(image) }
        if let loader = viewModel.instance.modLoader { return .loader(loader) }
        return .fallback
    }

    // MARK: - 个性化

    private var personalizationCard: some View {
        MyCard("个性化", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow("图标", labelWidth: 80) {
                    // 原版的图标是一排预设方块 / 物品的网格，这里同样开一个选择器，
                    // 不再只有「自动 / 自定义图片」两个选项。
                    HStack(spacing: 12) {
                        InstanceIconView(icon: icon)
                            .frame(width: 22, height: 22)
                        MyButton("选择图标…") { showingIconPicker = true }
                            .frame(width: 140)
                        Spacer(minLength: 0)
                    }
                }
                SettingRow("分类", labelWidth: 80) {
                    MySelect(categoryBinding, entries: categoryEntries)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 20) {
                    MyButton("修改版本名") { rename() }
                        .frame(width: 140)
                    MyButton("修改版本描述") { editDescription() }
                        .frame(width: 140)
                    MyButton(viewModel.isFavorite ? "取消收藏" : "加入收藏夹") {
                        viewModel.toggleFavorite()
                    }
                    .frame(width: 140)
                    Spacer()
                }
                .frame(height: 35)
                .padding(.top, 4)
            }
        }
    }

    private var categoryEntries: [String] {
        ["自动"] + viewModel.availableCategories + ["新建分类…"]
    }

    private var categoryBinding: Binding<String> {
        .init(
            get: { viewModel.instance.category ?? "自动" },
            set: { value in
                switch value {
                case "自动":
                    viewModel.setCategory("")
                case "新建分类…":
                    createCategory()
                default:
                    viewModel.setCategory(value)
                }
            }
        )
    }

    // MARK: - 快捷方式

    private var shortcutCard: some View {
        MyCard("快捷方式", foldable: false) {
            HStack(spacing: 20) {
                folderButton("root", "版本文件夹")
                folderButton("saves", "存档文件夹")
                folderButton("mods", "Mod 文件夹")
                folderButton("screenshots", "截图文件夹")
                Spacer()
            }
            .frame(height: 35)
        }
    }

    private func folderButton(_ key: String, _ title: String) -> some View {
        MyButton(title) {
            guard let folder = viewModel.folder(key) else { return }
            viewModel.open(folder)
        }
        .frame(width: 140)
    }

    // MARK: - 高级管理

    private var managementCard: some View {
        MyCard("高级管理", foldable: false) {
            HStack(spacing: 20) {
                MyButton("补全文件") {
                    viewModel.repair()
                }
                .frame(width: 140)
                MyButton("删除版本", type: .red) { confirmDelete() }
                    .frame(width: 140)
                Spacer()
            }
            .frame(height: 35)
        }
    }

    // MARK: - 交互

    private func confirmDelete() {
        MessageBoxManager.shared.showText(
            title: "确认",
            content: "你确定要删除这个版本（\(viewModel.displayTitle)）吗？\n这个版本的所有存档、模组、资源包等将会永久消失！（真的很久！）",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { result in
            if result == 1 {
                do {
                    try viewModel.deleteInstance()
                    hint("删除成功！", type: .finish)
                    AppRouter.shared.removeLast()
                } catch {
                    hint("删除版本失败：\(error.localizedDescription)", type: .critical)
                }
            }
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

    private func createCategory() {
        MessageBoxManager.shared.showInput(
            title: "输入分类名称",
            initialContent: "",
            placeholder: "例如：生存、科技、整合"
        ) { text in
            guard let text else { return }
            viewModel.setCategory(text)
            hint("分类已更新！", type: .finish)
        }
    }
}
