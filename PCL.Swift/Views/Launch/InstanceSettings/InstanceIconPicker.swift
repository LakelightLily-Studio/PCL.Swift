//
//  InstanceIconPicker.swift
//  PCL.Swift
//
//  实例图标选择器：第一格是「默认」（按加载器推导），第二格起是预设图标，
//  最后一格是「自定义…」（自己挑一张图片）。
//
//  预设图标从云端取（国内分发仓库的 assets/icons），拿不到时用打包在 App 里的同一张图；
//  开了「图标缓存」时云端那份会落盘，下次打开直接命中。
//

import SwiftUI
import AppKit
import Core

struct InstanceIconPicker: View {
    @ObservedObject private var viewModel: InstanceOverviewViewModel
    @Environment(\.dismiss) private var dismiss

    /// 六列，和原版图标选择器的排布一致。
    private let columns: [GridItem] = Array(repeating: GridItem(.fixed(64), spacing: 12), count: 6)

    init(viewModel: InstanceOverviewViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                MyText("选择实例图标", size: 16)
                Spacer(minLength: 0)
                MyText("图标来自云端，本地副本受「设置 → 其他 → 缓存 → 图标缓存」控制", size: 11, color: .colorGray3)
            }

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    defaultTile
                    ForEach(InstanceIconCatalog.presets) { icon in
                        InstancePresetTile(icon: icon, selected: viewModel.selectedIconID == icon.id) {
                            Task { await viewModel.setIcon(icon) }
                        }
                    }
                    customTile
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                MyButton("完成") { dismiss() }
                    .frame(width: 90)
            }
        }
        .padding(22)
        .frame(width: 540, height: 470)
        .background(Color.colorGray8)
    }

    /// 第一格：「默认」。清掉自定义图标，回到按加载器推导的图标。
    private var defaultTile: some View {
        InstanceIconTile(
            title: "默认",
            selected: viewModel.instance.customIconURL == nil,
            action: { viewModel.clearIcon() }
        ) {
            InstanceIconView(icon: viewModel.automaticIcon)
                .frame(width: 38, height: 38)
        }
    }

    /// 最后一格：自己挑一张图片。
    private var customTile: some View {
        InstanceIconTile(
            title: "自定义…",
            selected: viewModel.isCustomIconSelected,
            action: chooseImage
        ) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 22))
                .foregroundStyle(Color.color3)
        }
    }

    private func chooseImage() {
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
}

/// 一格图标：上方是图标，下方是名字，选中时描主题色边。
private struct InstanceIconTile<Icon: View>: View {
    private let title: String
    private let selected: Bool
    private let action: () -> Void
    private let icon: Icon

    init(
        title: String,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.selected = selected
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cardBackground)
                icon
                    .frame(width: 38, height: 38)
            }
            .frame(width: 64, height: 64)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selected ? Color.color3 : Color.colorGray2.opacity(0.4),
                        lineWidth: selected ? 2 : 1
                    )
            }
            MyText(title, size: 11, color: selected ? .color3 : .colorGray2)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// 一个预设图标格：先用本地那份（缓存 / 打包兜底）铺上，云端那份回来再换。
private struct InstancePresetTile: View {
    private let icon: InstancePresetIcon
    private let selected: Bool
    private let action: () -> Void

    @State private var image: NSImage?

    init(icon: InstancePresetIcon, selected: Bool, action: @escaping () -> Void) {
        self.icon = icon
        self.selected = selected
        self.action = action
    }

    var body: some View {
        InstanceIconTile(title: icon.name, selected: selected, action: action) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                } else {
                    Image(icon.asset)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                }
            }
            .frame(width: 38, height: 38)
        }
        .task(id: icon.id) { await load() }
    }

    private func load() async {
        image = InstanceIconStore.shared.immediateImage(for: icon)
        guard await InstanceIconStore.shared.refresh(icon) else { return }
        image = InstanceIconStore.shared.immediateImage(for: icon)
    }
}
