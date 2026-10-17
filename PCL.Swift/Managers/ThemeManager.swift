//
//  ThemeManager.swift
//  PCL.Mac
//

import SwiftUI
import Core

/// 主题色。
///
/// 只改「强调色」这一族（Color.color2 … Color.color8），文字色与灰阶不动：
/// 那几档是中性色，跟着变色会破坏对比度。
enum Theme: String, Codable, CaseIterable, CustomStringConvertible {
    case themeOrange
    case themeBlue

    var description: String {
        switch self {
        case .themeOrange: "主题橙"
        case .themeBlue: "主题蓝"
        }
    }

    /// 主色，用于标题栏、选中态与主按钮。
    var primary: Color {
        switch self {
        case .themeOrange: .init(0xF14710)
        case .themeBlue: .init(0x1370f3)
        }
    }

    /// 深一档，用于强调文字与悬停。
    var shade: Color {
        switch self {
        case .themeOrange: .init(0xC5390C)
        case .themeBlue: .init(0x0b5bcb)
        }
    }

    /// 浅一档，用于次级按钮与图标底。
    var tint: Color {
        switch self {
        case .themeOrange: .init(0xF46F44)
        case .themeBlue: .init(0x4890f5)
        }
    }

    /// 更浅，用于描边与分隔。
    var soft: Color {
        switch self {
        case .themeOrange: .init(0xF9AB91)
        case .themeBlue: .init(0x96c0f9)
        }
    }

    /// 极浅，用于选中背景。
    var faint: Color {
        switch self {
        case .themeOrange: .init(0xFCDBD1)
        case .themeBlue: .init(0xd5e6fd)
        }
    }

    /// 近乎背景，用于大面积填充。
    var wash: Color {
        switch self {
        case .themeOrange: .init(0xFDE3DB)
        case .themeBlue: .init(0xe0eafd)
        }
    }

    /// 最浅，用于图标前景与高光。
    var highlight: Color {
        switch self {
        case .themeOrange: .init(0xFEEBE5)
        case .themeBlue: .init(0xeaf2fe)
        }
    }

    /// 窗口底色。
    var background: Color {
        switch self {
        case .themeOrange: .init(0xFBE9E2)
        case .themeBlue: .init(0xC0DEF5)
        }
    }
}

/// 当前主题的唯一来源。
///
/// Color.colorN 是计算属性，直接读这里；切换主题后由 ContentView 上的 .id(theme) 触发重建。
final class ThemeManager: ObservableObject {
    static let shared: ThemeManager = .init()

    @Published private(set) var current: Theme

    private init() {
        current = LauncherConfig.shared.theme
    }

    func set(_ theme: Theme) {
        guard theme != current else { return }
        current = theme
        LauncherConfig.shared.theme = theme
        log("主题色已切换为 \(theme.description)")
    }
}
