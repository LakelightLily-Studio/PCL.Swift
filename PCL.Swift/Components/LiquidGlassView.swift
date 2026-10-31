//
//  LiquidGlassView.swift
//  PCL.Swift
//
//  导航栏（标题栏）背景的「液态玻璃」。
//
//  两层叠出来的：
//    1. NSVisualEffectView（.underWindowBackground + .behindWindow）：macOS 原生的那层磨砂模糊，
//       低版本系统上它就是全部——「不支持液态玻璃时退回原版模糊」；
//    2. macOS 26 起再加一层 NSGlassEffectView（真正的 Liquid Glass），负责折射与高光。
//  只留玻璃是不行的：NSGlassEffectView 不染色时几乎是透明的，背后的画面一点都没糊，
//  看起来就只是「标题栏变透明了」，所以模糊必须单独铺一层。
//
//  **不掺主题色**：玻璃只负责折射窗口背后的画面，颜色交给背景本身。
//  掺了主题色就不再是玻璃，而是一块带渐变的纯色板（FlClash 那类实现也是这个观感）。
//  代价是标题栏必须是深色字——浅色玻璃上白字会糊掉，所以 TitleBarView 按这一档切换前景色。
//
//  玻璃/模糊要透出窗口背后的画面，窗口本身不能是不透明的：
//  视图挂上来时把宿主窗口改成透明（isOpaque = false + 清空底色），
//  切回「纯色 / 线格」后视图被移出视图树，立刻恢复原样，其它页面不受影响。
//

import SwiftUI
import AppKit

/// 标题栏的液态玻璃背景。
struct LiquidGlassView: View {
    @ObservedObject private var config: LauncherConfigObserver = .shared

    /// 模糊程度 0…1，来自设置 → 个性化 → 标题栏 → 模糊程度。
    private var intensity: Double {
        Double(min(max(LauncherConfig.shared.navigationBarBlur, 0), 100)) / 100
    }

    var body: some View {
        ZStack {
            // 低版本系统上这就是全部：NSVisualEffectView 的材质是真正的磨砂模糊，
            // 档位（见 FrostedBackdrop.material）跟着滑块换，模糊强弱看得见。
            FrostedBackdrop(intensity: intensity)
            // 玻璃的不透明度跟着滑块走：低档几乎让开，露出下面那层（更薄的）模糊与窗口背后的画面；
            // 高档盖满，就是一块厚玻璃。
            //
            // 这是「模糊程度」能真正看得见的关键：NSGlassEffectView 的材质是固定的，
            // 既没有半径可调，也不会把叠在它下面的兄弟视图混进去——只调下面那些层，拖滑块毫无反应。
            GlassSurface()
                .opacity(0.25 + 0.75 * intensity)
            // 一层很淡的雾：补玻璃透明度变化之间的过渡，同时保证最低档也有点底——
            // 否则拖到 0 时标题栏几乎全透，浅色壁纸上的白字会看不清。
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.10 + 0.14 * intensity)
            WindowTranslucency()
        }
        .allowsHitTesting(false)
    }
}

/// 磨砂模糊层：macOS 原生的标题栏材质，窗口背后的画面会在这里被糊掉。
private struct FrostedBackdrop: NSViewRepresentable {
    let intensity: Double

    /// 材质没有半径可调，只能按档位换：越往下越糊、底色越不透明。
    private var material: NSVisualEffectView.Material {
        switch intensity {
        case ..<0.34: .underPageBackground
        case ..<0.67: .underWindowBackground
        default: .headerView
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view: NSVisualEffectView = .init()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? NSVisualEffectView, view.material != material else { return }
        view.material = material
    }
}

/// 液态玻璃层（macOS 26 起）。
private struct GlassSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else { return NSView() }
        let view: NSGlassEffectView = .init()
        view.style = .regular
        // 不染色：染色越重越像纯色板，玻璃自己的层次反而被盖掉。
        view.tintColor = nil
        // 默认圆角不是 0：不显式清掉的话，标题栏会变成一条两端带圆角的胶囊。
        view.cornerRadius = 0
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView else { return }
        glass.cornerRadius = 0
    }
}

/// 把宿主窗口改成透明，让玻璃能采样到窗口背后的画面。
///
/// 只在液态玻璃这一档挂载；视图被移出视图树时恢复窗口原来的不透明度与底色。
private struct WindowTranslucency: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowTranslucencyView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowTranslucencyView: NSView {
    private weak var configuredWindow: NSWindow?
    private var previousOpaque: Bool = true
    private var previousColor: NSColor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            restore()
            return
        }
        guard configuredWindow !== window else { return }
        restore()
        previousOpaque = window.isOpaque
        previousColor = window.backgroundColor
        window.isOpaque = false
        window.backgroundColor = .clear
        configuredWindow = window
    }

    private func restore() {
        guard let configuredWindow else { return }
        configuredWindow.isOpaque = previousOpaque
        configuredWindow.backgroundColor = previousColor ?? .windowBackgroundColor
        self.configuredWindow = nil
    }
}
