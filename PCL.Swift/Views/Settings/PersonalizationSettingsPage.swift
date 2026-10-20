//
//  PersonalizationSettingsPage.swift
//  PCL.Swift
//
//  设置 → 个性化：主题色与主页。
//
//  这两项原先都塞在「启动器」页的「个性化」卡片里，与下载源、日志导出混在一起；
//  拆成独立页后，外观相关的选项有固定入口，启动器页只留与运行行为有关的配置。
//

import SwiftUI
import Core

struct PersonalizationSettingsPage: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @State private var homepageType: LauncherConfig.HomepageType = LauncherConfig.shared.homepageType
    
    var body: some View {
        CardContainer {
            MyCard("主题色", foldable: false) {
                themePicker
            }
            
            MyCard("主页", foldable: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(LauncherConfig.HomepageType.allCases, id: \.self) { type in
                        // 二选一：已选中项再点不取消，否则会出现「一个都没选」的状态。
                        MyComboBox(checked: homepageBinding(type), text: type.description, allowsUncheck: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardIndex(1)
        }
    }
    
    /// 主题色卡片：与首次启动向导里「主题」那一步是同一套色卡。
    ///
    /// 向导里的 `themeCard` 是私有实现，这里照同样的观感重写一份，
    /// 差异只在容器：向导是整屏排开，这里放在设置页的卡片里。
    private var themePicker: some View {
        HStack(spacing: 16) {
            ForEach(Theme.allCases, id: \.self) { theme in
                themeCard(theme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func themeCard(_ theme: Theme) -> some View {
        let isCurrent: Bool = themeManager.current == theme
        // 整张色卡就是按钮：与向导里的取舍一致，用 DragGesture 接点击，
        // 避免嵌套在 ScrollView 里的 Button 抢走鼠标按住时的滚动手势。
        return cardBody(theme, isCurrent: isCurrent)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in themeManager.set(theme) }
            )
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }
    
    private func cardBody(_ theme: Theme, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.primary)
                    .frame(height: 26)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill([theme.tint, theme.soft, theme.faint][index])
                            .frame(height: 14)
                    }
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.background)
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
        .frame(width: 190)
        .background(Color.colorGray8, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? theme.primary : Color.clear, lineWidth: 2)
                // 描边层只是装饰：不关掉命中测试的话它会把整张卡片的点击吃掉。
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - 主页
    
    /// 主页是二选一：勾上某一项即取消另一项。`MyComboBox` 只认 `Binding<Bool>`，这里做转换。
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
