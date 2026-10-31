//
//  PageEntrance.swift
//  PCL.Swift
//
//  页面入场动画：按 PCL2（Plain Craft Launcher 2）的页面切换动画重写。
//
//  PCL2 的实现在 Controls/MyPageRight.vb 的 TriggerEnterAnimation：
//  每个参与动画的元素先被置成 opacity 0、translateY -16，然后同时启动三条动画——
//
//    · opacity → 1，100ms，AniEaseOutFluent(Weak)     = 1 - (1-t)²
//    · translateY +5，250ms，AniEaseOutFluent(Middle) = 1 - (1-t)³
//    · translateY +11，350ms，AniEaseOutBack(Middle)  = 1 - (1-t)^1.5 · cos(1.5πt)
//
//  第三条的 cos 项在后段会越过 1，所以位移末尾会冲过原位约 1.5pt 再落回来。
//
//  PCL2 的错峰计数器是"每个动画元素 +25ms"，元素列表里除了卡片本身还包括卡片内
//  每一个 TextBlock / MyHint / 按钮——所以相邻两张卡片之间实际隔了 100ms 以上，
//  这才是原版"从上到下依次出现"的观感来源。我们只对卡片错峰、拿不到卡片内的
//  控件数，于是把步长放大到 60ms 来还原同样的节奏。
//
//  SwiftUI 里同一个 offset 只能挂一条动画，没法把两条 translateY 相加，
//  所以这里用一个自绘的 Animatable 修饰器：外部用线性 350ms 把 progress 从 0 推到 1，
//  内部按上面的公式逐帧算出位移与透明度——叠加后的效果与 PCL2 一致，
//  而不是拿一条 spring 去"看起来差不多"。
//

import SwiftUI

/// 调试用：把动画整体放慢 N 倍，只由环境变量 `PCL_ANIM_SLOW` 控制（正常运行 = 1）。
///
/// 动画这种东西光看代码改不出来，得把过程录下来逐帧对。留着这个开关，
/// 以后改曲线/时序时可以直接 `PCL_ANIM_SLOW=6 ./PCL.Swift` 录慢动作。
enum PageAnimationDebug {
    static let factor: Double = {
        guard let raw = ProcessInfo.processInfo.environment["PCL_ANIM_SLOW"],
              let value = Double(raw),
              value > 0 else { return 1 }
        return value
    }()
}

enum PageEntrance {
    /// 整条位移动画的时长（对应 PCL2 里最长的那条 translateY）。
    static var duration: Double { 0.35 * PageAnimationDebug.factor }
    /// 相邻卡片之间的错峰。
    ///
    /// PCL2 的计数器是"每个页面级控件 +25ms"（卡片、提示条、按钮各算一格，
    /// 卡片内部不再遍历）。我们这里按卡片序号错峰，步长沿用 25ms。
    static var stagger: Double { 0.025 * PageAnimationDebug.factor }
    /// 错峰步数上限：8 步 = 0.2s。
    static let maxStaggerSteps: Int = 8

    /// 起始位置：目的地之上 16pt。
    static let startOffset: CGFloat = -16
    /// 第一段补的距离与时长：250ms 内补 5pt（easeOutQuad）。
    static let firstLift: CGFloat = 5
    static var firstLiftDuration: Double { 0.25 * PageAnimationDebug.factor }
    /// 第二段补完剩下的 11pt（350ms easeOutBack）。
    static let remainingLift: CGFloat = 11
    /// 淡入时长。
    static var fadeDuration: Double { 0.1 * PageAnimationDebug.factor }

    static func delay(for index: Int) -> Double {
        Double(min(max(index, 0), maxStaggerSteps)) * stagger
    }

    /// 整页入场动画的完整窗口：最长的那条位移动画 + 最大错峰。
    ///
    /// 页面里的异步内容（「更多」页的头像之类）要等这段时间过去再换成云端的新图：
    /// 动画中途换图会让卡片重绘，新图从零尺寸插进来，看起来就是图标在页面上"暂留"了一下。
    static var window: Double {
        duration + delay(for: maxStaggerSteps)
    }

    /// 驱动整条动画的 Animation（线性：曲线由 opacity/offset 自己算）。
    static func animation(for index: Int) -> Animation {
        .linear(duration: duration).delay(delay(for: index))
    }

    /// 给定线性进度（0…1 对应 0…350ms），算出当前透明度。
    static func opacity(at progress: Double) -> Double {
        let elapsed: Double = progress * duration
        return easeOutQuad(min(elapsed, fadeDuration) / fadeDuration)
    }

    /// 给定线性进度，算出当前位移。
    static func offset(at progress: Double) -> CGFloat {
        let elapsed: Double = progress * duration
        let first: Double = easeOutQuad(min(elapsed, firstLiftDuration) / firstLiftDuration)
        let second: Double = easeOutBack(min(elapsed, duration) / duration)
        return startOffset + firstLift * first + remainingLift * second
    }

    /// PCL2 的 AniEaseOutFluent(Weak)：1 - (1-t)²。
    private static func easeOutQuad(_ t: Double) -> Double {
        let clamped: Double = min(max(t, 0), 1)
        return 1 - (1 - clamped) * (1 - clamped)
    }

    /// PCL2 的 AniEaseOutBack(Middle)：1 - (1-t)^1.5 · cos(1.5πt)。
    private static func easeOutBack(_ t: Double) -> Double {
        let clamped: Double = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 1.5) * cos(1.5 * .pi * clamped)
    }

}

/// 左侧边栏的入场动画，对齐 PCL2 的 MyPageLeft.TriggerShowAnimation。
///
/// 每个条目从 x = -25 进来：先 200ms 的 easeOutQuad 补 5pt，
/// 再用 300ms 的 AniEaseOutBack(Weak)（p = 2）补剩下的 20pt，
/// 同时 100ms 内淡入；条目之间按原版的公式逐条错峰（见 `delay(for:)`）。
enum SidebarEntrance {
    static var duration: Double { 0.3 * PageAnimationDebug.factor }
    static let startOffset: CGFloat = -25
    static let firstLift: CGFloat = 5
    static let firstLiftDuration: Double = 0.2
    static let remainingLift: CGFloat = 20
    static var fadeDuration: Double { 0.1 * PageAnimationDebug.factor }

    /// 逐条目错峰，直接照抄 PCL2 的 `Delay += Math.Max(15 - Id, 7) * 2`：
    /// 第 0 条 0ms，之后每条依次多 30 / 28 / 26 / 24 / 22 / 20 / 18 / 16 / 14…ms，
    /// 累计就是 0、30、58、84、108、130、150、168、184、198…
    ///
    /// PCL2 的 `GetAllAnimControls` 把 MyListItem 整个算作**一格**（图标与文字不单独计数），
    /// 所以这里的序号与它一一对应，不需要再放大步长。
    static func delay(for index: Int) -> Double {
        var milliseconds: Double = 0
        for step in 0..<max(index, 0) {
            milliseconds += Double(max(15 - step, 7) * 2)
        }
        return milliseconds / 1000 * PageAnimationDebug.factor
    }

    static func opacity(at progress: Double) -> Double {
        let elapsed: Double = progress * duration
        let t: Double = min(max(min(elapsed, fadeDuration) / fadeDuration, 0), 1)
        return 1 - (1 - t) * (1 - t)
    }

    static func offset(at progress: Double) -> CGFloat {
        let elapsed: Double = progress * duration
        let firstT: Double = min(max(min(elapsed, firstLiftDuration) / firstLiftDuration, 0), 1)
        let first: Double = 1 - (1 - firstT) * (1 - firstT)
        let secondT: Double = min(max(min(elapsed, duration) / duration, 0), 1)
        // AniEaseOutBack(Weak)：p = 3 - 2 * 0.5 = 2
        let second: Double = 1 - pow(1 - secondT, 2) * cos(1.5 * .pi * secondT)
        return startOffset + firstLift * CGFloat(first) + remainingLift * CGFloat(second)
    }
}

struct SidebarEntranceShape: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(SidebarEntrance.opacity(at: progress))
            .offset(x: SidebarEntrance.offset(at: progress))
    }
}

/// 入场动画的实际绘制层：把 progress 映射成透明度与位移。
///
/// 单独拆出来是因为 `Animatable` 只能挂在最内层：外面一旦再套一个
/// 参与动画的修饰器（hover 之类），SwiftUI 就不会再按 animatableData 逐帧重绘了。
struct PageEntranceShape: ViewModifier, Animatable {
    var progress: Double
    let enabled: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(enabled ? PageEntrance.opacity(at: progress) : 1)
            .offset(y: enabled ? PageEntrance.offset(at: progress) : 0)
    }
}
