//
//  ThemeManager.swift
//  PCL.Mac
//

import SwiftUI
import Core

/// 一整套强调色。
///
/// 原版 PCL 的主题是「一个基色 + 一组派生色」，这里沿用同样的结构：
/// 只要给出基色，其余几档按固定比例与白/黑混合即可，不必手写十几个主题的
/// 全部色值（手写一定会漂移，改一个主题就会漏掉另一个）。
struct ThemePalette {
    /// 主色，用于标题栏、选中态与主按钮。
    let primary: Color
    /// 深一档，用于强调文字与悬停。
    let shade: Color
    /// 浅一档，用于次级按钮与图标底。
    let tint: Color
    /// 更浅，用于描边与分隔。
    let soft: Color
    /// 极浅，用于选中背景。
    let faint: Color
    /// 近乎背景，用于大面积填充。
    let wash: Color
    /// 最浅，用于图标前景与高光。
    let highlight: Color
    /// 窗口底色。
    let background: Color
}

/// 主题色。
///
/// 只改「强调色」这一族（Color.color2 … Color.color8），文字色与灰阶不动：
/// 那几档是中性色，跟着变色会破坏对比度。
enum Theme: String, Codable, CaseIterable, CustomStringConvertible {
    case themeOrange
    case themeBlue
    case themeTotoro
    case themeLemon
    case themeGrass
    case themePineapple
    case themeOak
    case themeMono
    case themePink
    case themePurple
    case themeAutumn
    case themeActive
    case themeRed
    case themeGeek
    /// 自定义：基色由 ThemeManager 里的 HSB 三值实时算出，不存色值。
    case custom

    var description: String {
        switch self {
        case .themeOrange: "主题橙"
        case .themeBlue: "主题蓝"
        case .themeTotoro: "龙猫蓝"
        case .themeLemon: "甜柠青"
        case .themeGrass: "小草绿"
        case .themePineapple: "菠萝黄"
        case .themeOak: "橡木棕"
        case .themeMono: "玄素黑"
        case .themePink: "铁杆粉"
        case .themePurple: "神秘紫"
        case .themeAutumn: "秋仪金"
        case .themeActive: "活跃橙"
        case .themeRed: "跳票红"
        case .themeGeek: "极客蓝"
        case .custom: "自定义"
        }
    }

    /// 预设主题的基色。自定义主题没有基色，由 HSB 现算。
    var baseHex: UInt? {
        switch self {
        case .themeOrange: 0xF14710
        case .themeBlue: 0x1370F3
        case .themeTotoro: 0x2F7FD1
        case .themeLemon: 0x11B7A5
        case .themeGrass: 0x3DA35D
        case .themePineapple: 0xE0A106
        case .themeOak: 0x8A6236
        case .themeMono: 0x4A4A4A
        case .themePink: 0xD6457F
        case .themePurple: 0x7B4FD1
        case .themeAutumn: 0xB8860B
        case .themeActive: 0xF57C00
        case .themeRed: 0xCE2111
        case .themeGeek: 0x0E7BD1
        case .custom: nil
        }
    }

    /// 该主题是否需要读取自定义 HSB。
    var isCustom: Bool { self == .custom }
}

/// 由基色派生整套色板。
///
/// 混合比例是照着眼睛调的：与白色混得越多越接近背景色，
/// 相邻两档之间要能看出层次，又不能浅到和白色卡片糊在一起。
enum ThemePaletteBuilder {
    typealias RGB = (r: Double, g: Double, b: Double)

    static func rgb(fromHex hex: UInt) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255.0,
         Double((hex >> 8) & 0xFF) / 255.0,
         Double(hex & 0xFF) / 255.0)
    }

    /// HSB → RGB。自定义主题用这一条把滑杆值变成基色。
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let h: Double = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let s: Double = min(max(saturation, 0), 1)
        let v: Double = min(max(brightness, 0), 1)
        if s <= 0 {
            return (v, v, v)
        }
        let sector: Double = h * 6
        let index: Int = Int(floor(sector))
        let fraction: Double = sector - Double(index)
        let p: Double = v * (1 - s)
        let q: Double = v * (1 - s * fraction)
        let t: Double = v * (1 - s * (1 - fraction))
        switch index % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.r + (b.r - a.r) * t,
         a.g + (b.g - a.g) * t,
         a.b + (b.b - a.b) * t)
    }

    static func color(_ rgb: RGB, alpha: Double = 1) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: alpha)
    }

    static func palette(from base: RGB) -> ThemePalette {
        let white: RGB = (1, 1, 1)
        let black: RGB = (0, 0, 0)
        return .init(
            primary: color(base),
            shade: color(mix(base, black, 0.22)),
            tint: color(mix(base, white, 0.18)),
            soft: color(mix(base, white, 0.50)),
            faint: color(mix(base, white, 0.78)),
            wash: color(mix(base, white, 0.88)),
            highlight: color(mix(base, white, 0.93)),
            background: color(mix(base, white, 0.90))
        )
    }
}

/// 当前主题的唯一来源。
///
/// Color.colorN 是计算属性，直接读这里；切换主题后由 ContentView 上的 .id(revision) 触发重建。
final class ThemeManager: ObservableObject {
    static let shared: ThemeManager = .init()

    @Published private(set) var current: Theme
    /// 自定义主题的色相（0…1）。
    @Published private(set) var customHue: Double
    /// 自定义主题的饱和度（0…1）。
    @Published private(set) var customSaturation: Double
    /// 自定义主题的明度（0…1）。
    @Published private(set) var customBrightness: Double

    /// 是否正处于"调整自定义主题"的窗口期。
    ///
    /// 为什么需要它：ContentView 靠 .id 重建整棵视图树来让新的强调色生效，
    /// 而 .id 一变，视图身份就变了——正在拖动的滑杆会被销毁重建，
    /// 手势中断，滑杆只能"点一下跳一段"，没法连续拖；侧边栏也会跟着重播入场动画。
    ///
    /// 所以拖动期间 **不** 改 revision（视图不重建，手势得以存活），
    /// 停手 0.5s 后才换 revision 让颜色生效；这个标记一直保持到 0.8s，
    /// 覆盖住那次重建，使各处的入场动画被跳过。
    @Published private(set) var isAdjustingCustomTheme: Bool = false

    /// 视图树的重建标识。只有它的变化才会让 ContentView 重建。
    ///
    /// 由 ThemeManager 自己维护而不是从属性拼出来：拼出来的话
    /// 拖滑杆时它每帧都变，正是上一条注释里那个问题的来源。
    @Published private(set) var revision: String = ""

    private var revisionCounter: Int = 0
    private var settleWorkItem: DispatchWorkItem?
    private var resetFlagWorkItem: DispatchWorkItem?

    private init() {
        let config: LauncherConfig = .shared
        current = config.theme
        customHue = config.themeHue
        customSaturation = config.themeSaturation
        customBrightness = config.themeBrightness
        revision = config.theme.rawValue + "-0"
        palette = ThemePaletteBuilder.palette(
            from: ThemePaletteBuilder.rgb(fromHex: config.theme.baseHex ?? 0xF14710)
        )
    }

    /// 当前色板。所有 Color.colorN 都从这里取。
    ///
    /// 缓存成存储属性：palette 每次构造要算 8 个混合色 + 8 个 Color 实例，
    /// 而 Color.color2…color8 与 colorBackground 每个都读一次 palette。
    /// 一个普通页面 body 里几十处颜色访问 = 几百次色板构造，这是设置页与
    /// 实例设置页切换卡顿的主因。缓存后只在主题真正变化时重算。
    @Published private(set) var palette: ThemePalette

    /// 重算色板。只在 current / custom* 变化后调用。
    private func rebuildPalette() {
        if current.isCustom {
            let rgb: ThemePaletteBuilder.RGB = ThemePaletteBuilder.rgb(
                hue: customHue,
                saturation: customSaturation,
                brightness: customBrightness
            )
            palette = ThemePaletteBuilder.palette(from: rgb)
        } else {
            palette = ThemePaletteBuilder.palette(from: ThemePaletteBuilder.rgb(fromHex: current.baseHex ?? 0xF14710))
        }
    }

    /// 各主题的色板缓存。
    ///
    /// 设置页要同时画出 15 张色卡，每张都要一个色板；palette(for:) 每次要算
    /// 8 个混合色，15 张就是 120 次混合，且每次 body 求值都会重算一遍。
    /// 预设主题的色板是常量，缓存起来即可；只有自定义主题会随滑杆变化。
    private var presetPaletteCache: [Theme: ThemePalette] = [:]

    /// 指定主题的色板。设置页要给每个候选主题画一张色卡，
    /// 那些卡片必须按各自的基色渲染，不能读"当前主题"。
    func palette(for theme: Theme) -> ThemePalette {
        if theme.isCustom {
            return palette
        }
        if let cached = presetPaletteCache[theme] {
            return cached
        }
        let built: ThemePalette = ThemePaletteBuilder.palette(
            from: ThemePaletteBuilder.rgb(fromHex: theme.baseHex ?? 0xF14710)
        )
        presetPaletteCache[theme] = built
        return built
    }

    func set(_ theme: Theme) {
        guard theme != current else { return }
        current = theme
        LauncherConfig.shared.theme = theme

        rebuildPalette()
        // 切预设主题：立刻换 revision，入场动画照常播放（这是期望的行为）。
        cancelPendingSettle()
        isAdjustingCustomTheme = false
        bumpRevision(theme.rawValue)
        log("主题色已切换为 \(theme.description)")
    }

    func setCustom(hue: Double, saturation: Double, brightness: Double) {
        customHue = min(max(hue, 0), 1)
        customSaturation = min(max(saturation, 0), 1)
        customBrightness = min(max(brightness, 0), 1)
        LauncherConfig.shared.themeHue = customHue
        LauncherConfig.shared.themeSaturation = customSaturation
        LauncherConfig.shared.themeBrightness = customBrightness

        if current != .custom {
            current = .custom
            LauncherConfig.shared.theme = .custom
        }
        // 色板立刻重算：设置页里的实时预览读的就是它，拖动时要能看见颜色在变。
        rebuildPalette()

        // 关键：拖动期间 **不动 revision**。
        // 视图树不重建 → 滑杆的手势不会被销毁 → 可以连续拖。
        isAdjustingCustomTheme = true

        settleWorkItem?.cancel()
        let settle: DispatchWorkItem = .init { [weak self] in
            guard let self else { return }
            // 换 revision：颜色在此刻生效。此时 isAdjustingCustomTheme 仍为 true，
            // 所以这次重建不会让卡片/侧边栏重播入场动画。
            self.bumpRevision("custom")
        }
        settleWorkItem = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: settle)

        resetFlagWorkItem?.cancel()
        let reset: DispatchWorkItem = .init { [weak self] in
            self?.isAdjustingCustomTheme = false
        }
        resetFlagWorkItem = reset
        // 0.8 > 0.5：保证重建发生在"抑制动画"的窗口内。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: reset)
    }

    private func bumpRevision(_ prefix: String) {
        revisionCounter += 1
        revision = "\(prefix)-\(revisionCounter)"
    }

    private func cancelPendingSettle() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        resetFlagWorkItem?.cancel()
        resetFlagWorkItem = nil
    }
}
