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

    // MARK: - 图标选择

    /// 下拉里的全部选项：默认 → 27 个预设（草方块第二）→ 自定义…
    private var iconChoices: [InstanceIconChoice] {
        [.automatic] + InstanceIconCatalog.presets.map { .preset($0) } + [.custom]
    }

    /// 当前选中项。来源只有一个：实例元数据里的 customIconURL / customIconName。
    private var iconBinding: Binding<InstanceIconChoice> {
        .init(
            get: {
                if let name = viewModel.instance.customIconName,
                   let preset = InstanceIconCatalog.icon(id: name) {
                    return .preset(preset)
                }
                return viewModel.instance.customIconURL == nil ? .automatic : .custom
            },
            set: { choice in
                switch choice {
                case .automatic:
                    viewModel.clearIcon()
                case .preset(let icon):
                    // 选中哪一个才去云端取哪一个（内存 → 磁盘缓存 → 云端 → 打包兜底）。
                    Task { await viewModel.setIcon(icon) }
                case .custom:
                    chooseIcon()
                }
            }
        )
    }

    /// 下拉每一行的图标：默认按实例的加载器推导，其余用各自打包的内置图。
    private func iconName(for choice: InstanceIconChoice) -> String? {
        switch choice {
        case .automatic:
            switch viewModel.instance.modLoader {
            case .fabric: "iconFabric"
            case .forge: "iconForge"
            case .neoforge: "iconNeoforge"
            case nil: "iconGrassBlock"
            }
        case .preset(let icon):
            icon.asset
        case .custom:
            nil
        }
    }

    /// 自定义图片：选完直接把文件复制进实例目录。
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

    // MARK: - 个性化

    private var personalizationCard: some View {
        MyCard("个性化", foldable: false) {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow("图标", labelWidth: 80) {
                    // 和原版一样是个下拉框：默认 / 各预设图标 / 自定义…。
                    // 下拉里只显示打包在 App 里的那张图，**选中哪一个才去云端取哪一个**，
                    // 不是打开就一口气拉 27 张。
                    MySelect(iconBinding, entries: iconChoices, icon: iconName(for:))
                        .frame(maxWidth: .infinity)
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
