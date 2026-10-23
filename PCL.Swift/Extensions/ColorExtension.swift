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
    static let color1: Color = .init(0x343d4a)
    static let colorGray1: Color = .init(0x404040)
    static let colorGray2: Color = .init(0x737373)
    static let colorGray3: Color = .init(0x8c8c8c)
    static let colorGray4: Color = .init(0xa6a6a6)
    static let colorGray5: Color = .init(0xcccccc)
    static let colorGray6: Color = .init(0xebebeb)
    static let colorGray7: Color = .init(0xf0f0f0)
    static let colorGray8: Color = .init(0xf5f5f5)

    /// 窗口底色，随主题变化。
    static var colorBackground: Color { ThemeManager.shared.palette.background }

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
