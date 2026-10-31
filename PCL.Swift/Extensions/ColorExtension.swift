//
//  ColorExtension.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/13.
//

import SwiftUI

extension Color {
    // https://github.com/CylorineStudio/PCL.Mac.Refactor/issues/13
    // https://github.com/PCL-Community/PCL2-CE/blob/cf2ddb8cbd2a3edc00ebd9ebf7533b0ba7b7de10/Plain%20Craft%20Launcher%202/Application.xaml#L28-L84
    //
    // color2 … color8 是强调色阶梯，随主题变化；其余是中性色，固定不变。
    // 阶梯不再逐个写死：预设主题只给一个基色，其余档位由 ThemePaletteBuilder 按固定比例混出来。
    static var color2: Color { ThemeManager.shared.palette.shade }
    static var color3: Color { ThemeManager.shared.palette.primary }
    static var color4: Color { ThemeManager.shared.palette.tint }
    static var color5: Color { ThemeManager.shared.palette.soft }
    static var color6: Color { ThemeManager.shared.palette.faint }
    static var color7: Color { ThemeManager.shared.palette.wash }
    static var color8: Color { ThemeManager.shared.palette.highlight }
    static var colorBg0: Color { ThemeManager.shared.palette.soft }
    static var colorBg1: Color { ThemeManager.shared.palette.wash.opacity(0.75) }

    // 中性色：浅色下是"深字浅底"，深色下整体翻过来（文字变亮、灰阶变暗）。
    // 它们是计算属性而不是常量——外观切换后视图重建时会重新取值，
    // 常量则会被静态初始化时的那一套颜色钉死。
    /// 主文字色。
    static var color1: Color { isDark ? .init(0xE6E8EC) : .init(0x343d4a) }
    static var colorGray1: Color { isDark ? .init(0xD6D6D6) : .init(0x404040) }
    static var colorGray2: Color { isDark ? .init(0xA8A8A8) : .init(0x737373) }
    static var colorGray3: Color { isDark ? .init(0x8C8C8C) : .init(0x8c8c8c) }
    static var colorGray4: Color { isDark ? .init(0x6E6E6E) : .init(0xa6a6a6) }
    static var colorGray5: Color { isDark ? .init(0x4A4A4A) : .init(0xcccccc) }
    static var colorGray6: Color { isDark ? .init(0x333333) : .init(0xebebeb) }
    static var colorGray7: Color { isDark ? .init(0x262626) : .init(0xf0f0f0) }
    static var colorGray8: Color { isDark ? .init(0x1B1B1B) : .init(0xf5f5f5) }

    /// 窗口底色，随主题与深浅色变化。
    static var colorBackground: Color { ThemeManager.shared.palette.background }

    /// 卡片 / 弹窗 / 下拉面板的底色。
    ///
    /// 浅色沿用 PCL2 的 Color.FromArgb(245,255,255,255)（近白，不是灰）；
    /// 深色用比页面底色亮一档的深灰，卡片才能从背景里浮出来。
    static var cardBackground: Color {
        isDark ? .init(0x2A2C31).opacity(0.97) : .white.opacity(245.0 / 255.0)
    }

    /// 侧边栏底板。
    static var sidebarBackground: Color { isDark ? .init(0x202226) : .white }

    /// 当前是不是深色外观。
    static var isDark: Bool { ThemeManager.shared.isDark }

    init(_ hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
