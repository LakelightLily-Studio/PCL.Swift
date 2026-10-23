//
//  PersonalizationSettingsPage.swift
//  PCL.Swift
//
//  设置 → 个性化：主题色、背景与标题栏。
//
//  主题从"两个写死的枚举"扩成"一个基色 + 派生阶梯"后，色卡数量涨到 15 个，
//  排成一行会超出窗口宽度，所以改成可横向滚动的色卡条 + 一个自定义色卡。
//

import SwiftUI
import Core

struct PersonalizationSettingsPage: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var config: LauncherConfigObserver = .shared
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType

    var body: some View {
        CardContainer {
            themeCard
            customThemeCard
                .cardIndex(1)
            backgroundCard
                .cardIndex(2)
            titleBarCard
                .cardIndex(3)
            MyCard("主页", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(LauncherConfig.HomepageType.allCases, id: \.self) { type in
                        // 二选一：已选中项再点不取消，否则会出现「一个都没选」的状态。
                        MyComboBox(checked: homepageBinding(type), text: type.description, allowsUncheck: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardIndex(4)
        }
    }

    // MARK: - 主题色

    private var themeCard: some View {
        MyCard("主题色", foldable: false) {
            // 横向滚动 + 常显滚动条：15 个色卡一屏放不下，
            // 不显示滚动条时用户不会意识到右边还有内容。
            ScrollView(.horizontal, showsIndicators: true) {
                // LazyHStack：只构建可见的几张卡，15 张全建出来会让切页明显变慢。
                LazyHStack(spacing: 12) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        themeCardView(theme)
                    }
                }
                .padding(.vertical, 2)
                .padding(.bottom, 8)
            }
            .alwaysShowScrollIndicators()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 150)
        }
    }

    private func themeCardView(_ theme: Theme) -> some View {
        let isCurrent: Bool = themeManager.current == theme
        // 整张色卡就是按钮：与向导里的取舍一致，用 DragGesture 接点击，
        // 避免嵌套在 ScrollView 里的 Button 抢走鼠标按住时的滚动手势。
        return cardBody(theme, isCurrent: isCurrent)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in themeManager.set(theme) }
            )
    }

    private func cardBody(_ theme: Theme, isCurrent: Bool) -> some View {
        let palette: ThemePalette = themeManager.palette(for: theme)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.primary)
                    .frame(height: 26)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill([palette.tint, palette.soft, palette.faint][index])
                            .frame(height: 14)
                    }
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.background)
                    .frame(height: 18)
            }
            .padding(10)

            HStack(spacing: 6) {
                Text(theme.description)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.color1)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.color3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 150)
        .background(Color.colorGray8, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? palette.primary : Color.clear, lineWidth: 2)
                // 描边层只是装饰：不关掉命中测试的话它会把整张卡片的点击吃掉。
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 自定义主题

    private var customThemeCard: some View {
        StaticCard("自定义主题") {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("色调", labelWidth: 70) {
                    MySlider(value: Binding(
                        get: { themeManager.customHue },
                        set: { themeManager.setCustom(hue: $0, saturation: themeManager.customSaturation, brightness: themeManager.customBrightness) }
                    ), range: 0...1)
                }
                SettingRow("饱和度", labelWidth: 70) {
                    MySlider(value: Binding(
                        get: { themeManager.customSaturation },
                        set: { themeManager.setCustom(hue: themeManager.customHue, saturation: $0, brightness: themeManager.customBrightness) }
                    ), range: 0...1)
                }
                SettingRow("亮度", labelWidth: 70) {
                    MySlider(value: Binding(
                        get: { themeManager.customBrightness },
                        set: { themeManager.setCustom(hue: themeManager.customHue, saturation: themeManager.customSaturation, brightness: $0) }
                    ), range: 0.2...1)
                }
                // 拖动滑杆即生效，不再需要"应用"按钮。
            }
        }
    }

    // MARK: - 背景

    private var backgroundCard: some View {
        MyCard("背景图片", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MyButton("选择图片") { chooseBackground() }
                        .frame(width: 110)
                    MyButton("清除背景") {
                        LauncherConfig.shared.backgroundImageURL = nil
                        config.touch()
                        hint("已清除背景图片！", type: .finish)
                    }
                    .frame(width: 110)
                    .disabled(LauncherConfig.shared.backgroundImageURL == nil)
                    Spacer()
                }
                .frame(height: 35)

                SettingRow("不透明度", labelWidth: 90) {
                    MySlider(value: Binding(
                        get: { LauncherConfig.shared.backgroundOpacity },
                        set: { LauncherConfig.shared.backgroundOpacity = $0; config.touch() }
                    ), range: 0...1)
                }
                SettingRow("模糊", labelWidth: 90) {
                    MySlider(value: Binding(
                        get: { LauncherConfig.shared.backgroundBlur },
                        set: { LauncherConfig.shared.backgroundBlur = $0; config.touch() }
                    ), range: 0...40)
                }
                SettingRow("自适应方式", labelWidth: 90) {
                    MyComboBox(checked: Binding(
                        get: { LauncherConfig.shared.backgroundFills },
                        set: { LauncherConfig.shared.backgroundFills = $0; config.touch() }
                    ), text: "填充（裁切多余部分）")
                    Spacer(minLength: 0)
                }
                SettingRow("叠加主题色", labelWidth: 90) {
                    MyComboBox(checked: Binding(
                        get: { LauncherConfig.shared.backgroundTinted },
                        set: { LauncherConfig.shared.backgroundTinted = $0; config.touch() }
                    ), text: "在背景图上叠加一层主题色")
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 标题栏

    private var titleBarCard: some View {
        MyCard("标题栏", foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                SettingRow("显示内容", labelWidth: 90) {
                    MySelect(Binding(
                        get: { LauncherConfig.shared.titleBarLogoType },
                        set: { LauncherConfig.shared.titleBarLogoType = $0; config.touch() }
                    ), entries: TitleBarLogoType.allCases)
                    .frame(width: 150)
                }
                if LauncherConfig.shared.titleBarLogoType == .text {
                    SettingRow("文本", labelWidth: 90) {
                        MyTextField(text: Binding(
                            get: { LauncherConfig.shared.titleBarText },
                            set: { LauncherConfig.shared.titleBarText = $0; config.touch() }
                        ), placeholder: "标题栏文字")
                    }
                }
                if LauncherConfig.shared.titleBarLogoType == .image {
                    HStack {
                        MyButton("选择图片") { chooseTitleBarImage() }
                            .frame(width: 110)
                        MyButton("清除图片") {
                            LauncherConfig.shared.titleBarImageURL = nil
                            config.touch()
                        }
                        .frame(width: 110)
                        .disabled(LauncherConfig.shared.titleBarImageURL == nil)
                        Spacer()
                    }
                    .frame(height: 35)
                }
            }
        }
    }

    // MARK: - 交互

    private func chooseBackground() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.title = "选择背景图片"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            LauncherConfig.shared.backgroundImageURL = url
            config.touch()
            hint("背景图片已更新！", type: .finish)
        }
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

    // MARK: - 主页

    /// 主页是二选一：勾上某一项即取消另一项。MyComboBox 只认 Binding<Bool>，这里做转换。
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
}
