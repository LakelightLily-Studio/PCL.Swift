//
//  PersonalizationSettingsPage.swift
//  PCL.Swift
//
//  设置 → 个性化：主题、背景与标题栏。
//
//  卡片与顺序对齐 PCL2 的 PageSetupUI：基础 / 背景图片 / 标题栏 / 主页。
//  按要求刻意不做的两张卡：背景音乐（本启动器没有音频子系统）、功能隐藏
//  （没有可隐藏的功能入口）。
//
//  主题仍是下拉列表而不是原版的 15 张色卡：色卡排成一行要横向滚动，既占地方，
//  也没法一眼看全；候选色卡在向导里仍然保留（那边需要可视化挑选）。
//

import SwiftUI
import Core

struct PersonalizationSettingsPage: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var config: LauncherConfigObserver = .shared
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType
    @State private var titleBarLogoType: TitleBarLogoType = LauncherConfig.shared.titleBarLogoType

    var body: some View {
        CardContainer {
            basicCard
            titleBarCard
                .cardIndex(1)
            homeCard
                .cardIndex(2)
        }
    }

    // MARK: - 基础

    /// 基础：主题（含自定义的三条滑杆）。
    ///
    /// PCL2 把「自定义」做成主题网格里的一项，选中后才展开色调/饱和度/亮度；
    /// 这里同理——选中网格里的「自定义」才出现下面三行，不额外占一张卡。
    private var basicCard: some View {
        MyCard("基础", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("主题", labelWidth: 120, verticalPadding: 2) {
                    // 与 PCL2 一致：五列单选，名字逐行排开，不做成下拉。
                    // 选中后由 MyComboBox 把勾选色换成主题色，本身就是一个色卡。
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 5),
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            MyComboBox(checked: themeBinding(theme), text: theme.description, allowsUncheck: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if themeManager.current == .custom {
                    SettingRow("色调", labelWidth: 120) {
                        MySlider(value: Binding(
                            get: { themeManager.customHue },
                            set: { themeManager.setCustom(hue: $0, saturation: themeManager.customSaturation, brightness: themeManager.customBrightness) }
                        ), range: 0...1)
                    }
                    SettingRow("饱和度", labelWidth: 120) {
                        MySlider(value: Binding(
                            get: { themeManager.customSaturation },
                            set: { themeManager.setCustom(hue: themeManager.customHue, saturation: $0, brightness: themeManager.customBrightness) }
                        ), range: 0...1)
                    }
                    SettingRow("亮度", labelWidth: 120) {
                        MySlider(value: Binding(
                            get: { themeManager.customBrightness },
                            set: { themeManager.setCustom(hue: themeManager.customHue, saturation: themeManager.customSaturation, brightness: $0) }
                        ), range: 0.2...1)
                    }
                    // 拖动滑杆即生效，不再需要"应用"按钮。
                }

            }
        }
    }


    // MARK: - 标题栏

    /// 标题栏：四项单选（无 / 默认 / 文本 / 图片）+ 随选项展开的输入区，与 PCL2 一致。
    private var titleBarCard: some View {
        MyCard("标题栏", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 26) {
                    ForEach(TitleBarLogoType.allCases, id: \.self) { type in
                        MyComboBox(checked: logoTypeBinding(type), text: type.description, allowsUncheck: false)
                    }
                    Spacer(minLength: 0)
                }

                if titleBarLogoType == .text {
                    SettingRow("标题栏文本", labelWidth: 120) {
                        MyTextField(text: Binding(
                            get: { LauncherConfig.shared.titleBarText },
                            set: { LauncherConfig.shared.titleBarText = $0; config.touch() }
                        ), placeholder: "标题栏文字")
                    }
                }

                if titleBarLogoType == .image {
                    HStack(spacing: 20) {
                        MyButton("更改图片") { chooseTitleBarImage() }
                            .frame(width: 120)
                        MyButton("清空图片", type: .red) {
                            LauncherConfig.shared.titleBarImageURL = nil
                            config.touch()
                        }
                        .frame(width: 120)
                        .disabled(LauncherConfig.shared.titleBarImageURL == nil)
                        Spacer()
                    }
                    .frame(height: 35)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - 主页

    private var homeCard: some View {
        MyCard("主页", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 5),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(LauncherConfig.HomepageType.allCases, id: \.self) { type in
                        // 单选：已选中项再点不取消，否则会出现「一个都没选」的状态。
                        MyComboBox(checked: homepageBinding(type), text: type.description, allowsUncheck: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                switch LauncherConfig.shared.homepageType {
                case .preset:
                    SettingRow("主页预设", labelWidth: 90) {
                        MySelect(Binding(
                            get: { LauncherConfig.shared.homepagePreset },
                            set: { LauncherConfig.shared.homepagePreset = $0; config.touch() }
                        ), entries: LauncherConfig.HomepagePreset.allCases)
                        .frame(maxWidth: .infinity)
                    }
                case .local:
                    HStack(spacing: 20) {
                        MyButton("打开主页文件夹") {
                            NSWorkspace.shared.open(HomepageLoader.localFileURL.deletingLastPathComponent())
                        }
                        .frame(width: 130)
                        MyButton("刷新主页") {
                            if !FileManager.default.fileExists(atPath: HomepageLoader.localFileURL.path) {
                                hint("还没有 Custom.xaml，已为你打开文件夹。", type: .critical)
                                NSWorkspace.shared.open(HomepageLoader.localFileURL.deletingLastPathComponent())
                                return
                            }
                            config.touch()
                        }
                        .frame(width: 110)
                        Spacer()
                    }
                    .frame(height: 35)
                    MyText("主页文件：" + HomepageLoader.localFileURL.path, size: 12, color: .colorGray3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                case .remote:
                    SettingRow("下载地址", labelWidth: 90) {
                        MyTextField(text: Binding(
                            get: { LauncherConfig.shared.homepageURL },
                            set: { LauncherConfig.shared.homepageURL = $0 }
                        ), placeholder: "https://example.com/Custom.xaml")
                        .onChange(of: LauncherConfig.shared.homepageURL) { _ in config.touch() }
                    }
                case .empty, .demo:
                    EmptyView()
                }

                MyTip(text: "主页自定义仍处于测试阶段，渲染开销较大、性能可能不佳，请酌情使用；自定义主页还会执行网页跳转与弹窗，请谨慎使用陌生人提供的主页。", theme: .yellow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 交互

    /// 主题单选。选中值直接落到 ThemeManager：它会一并写回 LauncherConfig 并刷新色板。
    private func themeBinding(_ theme: Theme) -> Binding<Bool> {
        .init(
            get: { themeManager.current == theme },
            set: { checked in
                guard checked else { return }
                themeManager.set(theme)
            }
        )
    }

    /// 标题栏四项单选。MyComboBox 只认 Binding<Bool>，这里把「点自己」翻译成选中。
    private func logoTypeBinding(_ type: TitleBarLogoType) -> Binding<Bool> {
        .init(
            get: { titleBarLogoType == type },
            set: { checked in
                guard checked else { return }
                titleBarLogoType = type
                LauncherConfig.shared.titleBarLogoType = type
                config.touch()
            }
        )
    }

    /// 主页是二选一：勾上某一项即取消另一项。
    private func homepageBinding(_ type: LauncherConfig.HomepageType) -> Binding<Bool> {
        .init(
            get: { homepageType == type },
            set: { checked in
                guard checked else { return }
                homepageType = type
                LauncherConfig.shared.homepageType = type
            }
        )
    }

    private func chooseTitleBarImage() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.title = "选择标题栏图片"
        panel.begin { result in
            guard result == .OK else { return }
            LauncherConfig.shared.titleBarImageURL = panel.url
            config.touch()
        }
    }
}
