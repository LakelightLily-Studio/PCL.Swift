//
//  PersonalizationSettingsPage.swift
//  PCL.Swift
//
//  设置 → 个性化：主题、背景图片与标题栏。
//
//  卡片与顺序对齐 PCL2 的 PageSetupUI：基础 / 背景图片 / 标题栏 / 主页。
//  按要求刻意不做的两张卡：背景音乐（本启动器没有音频子系统）、功能隐藏
//  （没有可隐藏的功能入口）。
//
//  单选一律用圆形单选框（MyRadioBox），与原版一致；可多选的开关才用方形复选框。
//

import SwiftUI
import Core

struct PersonalizationSettingsPage: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var config: LauncherConfigObserver = .shared
    @ObservedObject private var backgroundImageManager: BackgroundImageManager = .shared
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType
    @State private var titleBarLogoType: TitleBarLogoType = LauncherConfig.shared.titleBarLogoType
    /// 背景图片的四个设置。改动即生效，落盘由 LauncherConfig 自己防抖。
    @State private var backgroundSuit: BackgroundImageSuit = LauncherConfig.shared.backgroundImageSuit
    @State private var backgroundOpacity: Double = Double(LauncherConfig.shared.backgroundImageOpacity)
    @State private var backgroundBlur: Double = Double(LauncherConfig.shared.backgroundImageBlur)
    @State private var colorfulBackground: Bool = LauncherConfig.shared.backgroundColorful

    var body: some View {
        CardContainer {
            basicCard
            backgroundCard
                .cardIndex(1)
            titleBarCard
                .cardIndex(2)
            homeCard
                .cardIndex(3)
        }
        .onAppear {
            // 进页面时重新数一遍文件夹：用户可能在访达里刚放了几张图。
            backgroundImageManager.refresh(random: false)
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
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 5),
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            MyRadioBox(checked: themeBinding(theme), text: theme.description)
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

    // MARK: - 背景图片

    /// 背景图片。与 PCL2 的 CardBackground 一致：
    /// 只有文件夹里真的有图片时才展开自适应方式 / 不透明度 / 模糊与「清空」。
    private var backgroundCard: some View {
        MyCard(backgroundCardTitle, foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                // 有图（指定的或文件夹里的）才展开这些选项。
                if backgroundImageManager.fileURL != nil {
                    SettingRow("自适应方式", labelWidth: 120) {
                        MySelect($backgroundSuit, entries: BackgroundImageSuit.allCases)
                            .frame(maxWidth: .infinity)
                            .onChange(of: backgroundSuit) { newValue in
                                LauncherConfig.shared.backgroundImageSuit = newValue
                                config.touch()
                            }
                    }

                    SettingRow("不透明度", labelWidth: 120) {
                        MySlider(value: $backgroundOpacity, range: 0...1000, step: 1)
                            .onChange(of: backgroundOpacity) { newValue in
                                LauncherConfig.shared.backgroundImageOpacity = Int(newValue)
                                config.touch()
                            }
                        MyText("\(Int((backgroundOpacity / 10).rounded()))%", size: 12, color: .colorGray3)
                            .frame(width: 48, alignment: .trailing)
                    }

                    SettingRow("背景模糊", labelWidth: 120) {
                        MySlider(value: $backgroundBlur, range: 0...40, step: 1)
                            .onChange(of: backgroundBlur) { newValue in
                                LauncherConfig.shared.backgroundImageBlur = Int(newValue)
                                config.touch()
                            }
                        MyText("\(Int(backgroundBlur)) 像素", size: 12, color: .colorGray3)
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                MyComboBox(checked: $colorfulBackground, text: "叠加彩色背景")
                    .padding(.leading, 6)
                    .onChange(of: colorfulBackground) { newValue in
                        LauncherConfig.shared.backgroundColorful = newValue
                        config.touch()
                    }

                HStack(spacing: 20) {
                    MyButton("选择图片") {
                        chooseBackgroundImage()
                    }
                    .frame(width: 120)
                    // 「清除」取代了原来的「刷新背景图片」：现在背景由用户指定，
                    // 需要的动作是「把背景去掉」，而不是「再随机换一张」。
                    if backgroundImageManager.fileURL != nil {
                        MyButton("清除", type: .red) {
                            confirmClearBackgroundImage()
                        }
                        .frame(width: 120)
                    }
                    Spacer()
                }
                .frame(height: 35)

                if let url = backgroundImageManager.fileURL {
                    MyText("当前图片：" + url.lastPathComponent, size: 12, color: .colorGray3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var backgroundCardTitle: String {
        // 指定了单张图片时就不报文件夹里的张数了，那和当前显示的图没关系。
        guard LauncherConfig.shared.backgroundImageURL == nil else { return "背景图片" }
        let count: Int = backgroundImageManager.imageCount
        return count > 0 ? "背景图片（\(count) 张）" : "背景图片"
    }
    
    /// 选一张图片直接当背景（不再随机）。
    private func chooseBackgroundImage() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.title = "选择背景图片"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            backgroundImageManager.select(url)
            config.touch()
        }
    }

    /// 清除背景图片：解除指定、删掉图片文件夹里的图、并把当前背景撤下来。
    private func confirmClearBackgroundImage() {
        MessageBoxManager.shared.showText(
            title: "清除背景图片",
            content: "将移除当前的背景图片，并删除背景图片文件夹中的所有文件。\n此操作不可撤销，是否确定？",
            level: .error,
            .no(),
            .yes(type: .red)
        ) { button in
            guard button == 1 else { return }
            backgroundImageManager.clear()
            config.touch()
            hint("背景图片已清除！", type: .finish)
        }
    }

    // MARK: - 标题栏

    /// 标题栏：四项单选（无 / 默认 / 文本 / 图片）+ 随选项展开的输入区，与 PCL2 一致。
    private var titleBarCard: some View {
        MyCard("标题栏", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("导航栏背景", labelWidth: 120) {
                    MySelect(Binding(
                        get: { LauncherConfig.shared.navigationBarBackground },
                        set: { LauncherConfig.shared.navigationBarBackground = $0; config.touch() }
                    ), entries: NavigationBarBackground.allCases)
                    .frame(maxWidth: .infinity)
                }

                // 原版是 1*、1*、1*、1*、0.2* 五列：四项均分，右边留一点空白。
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 5),
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(TitleBarLogoType.allCases, id: \.self) { type in
                        MyRadioBox(checked: logoTypeBinding(type), text: type.description)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                        MyRadioBox(checked: homepageBinding(type), text: type.description)
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

    /// 标题栏四项单选。MyRadioBox 只认 Binding<Bool>，这里把「点自己」翻译成选中。
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

    /// 主页是单选：勾上某一项即取消其他项。
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
