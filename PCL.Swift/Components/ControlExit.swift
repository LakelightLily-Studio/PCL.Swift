//
//  ControlExit.swift
//  PCL.Swift
//
//  控件退场动画：按 PCL2（Plain Craft Launcher 2）的页面切换退场重写。
//
//  PCL2 的实现在 Controls/MyPageRight.vb 的 TriggerExitAnimation：
//
//    · 每个参与动画的控件 70ms 淡出（AaOpacity(Control, -1, 70, Delay)）
//    · 同时 70ms 上移 6pt（AaTranslateY(Control, -6, 70, Delay)）
//    · 相邻控件错峰 15ms，计数器只数"页面级控件"（卡片 / 提示条 / 按钮）
//    · 最后一条 AaCode 带 After = True，等整组动画跑完才把容器折叠
//
//  这两条 Aa 都没给 Ease，走的是默认的 AniEaseLinear——**退场是线性的**。
//  别顺手换成 easeOut：入场那套曲线是 AniEaseOutBack，退场不是，
//  曲线一换整段就会慢半拍、看起来"粘"在屏幕上。
//
//  PCL2 的切页时序（FormMain.PageChangeAnim）：
//    t=0       旧页面开始退场，侧边栏同时退场
//    t=110ms   容器里换成新页面（旧页面 PageOnForceExit 强制折叠，没跑完的退场就此中断）
//    t=140ms   新页面开始入场
//  我们不在 110ms 硬切：卡片多的时候，第 4 张之后本来还在半透明状态，
//  硬切会看见它们"啪"地消失。这里让退场自然跑完（PageExit.window = 130ms）再换页面，
//  观感与 PCL2 一致，但不会出现半透明残影。
//

import SwiftUI

/// 页面内容退场：MyCard / StaticCard。
enum PageExit {
    /// 单个控件的淡出时长（PCL2：AaOpacity(Control, -1, 70, Delay)）。
    static var duration: Double { 0.07 * PageAnimationDebug.factor }
    /// 相邻控件的错峰（PCL2：Delay += 15）。
    static var stagger: Double { 0.015 * PageAnimationDebug.factor }
    /// 错峰步数上限。
    ///
    /// PCL2 不封顶，但它自己在 110ms 就把容器换掉了：第 4 个控件（delay 45ms）
    /// 刚好在 115ms 结束，再往后的本来就看不见。这里同样封 4 步，
    /// 让整段退场在 130ms 内跑完，切换点也就和原版对齐。
    static let maxStaggerSteps: Int = 4
    /// 控件上移的距离（PCL2：AaTranslateY(Control, -6, 70, Delay)）。
    static let offset: CGFloat = -6

    /// 从开始退场到可以换页面的总时长。
    static var window: Double { duration + stagger * Double(maxStaggerSteps) }

    static func delay(for index: Int) -> Double {
        Double(min(max(index, 0), maxStaggerSteps)) * stagger
    }

    /// 驱动单张卡片退场的动画（线性：位移与透明度都按线性插值）。
    static func animation(for index: Int) -> Animation {
        .linear(duration: duration).delay(delay(for: index))
    }
}

/// 侧边栏退场。
///
/// PCL2 的 MyPageLeft 有两套退场，取决于 XAML 里有没有写 AnimatedControl：
///
/// - 有（下载 / 设置 / 更多 / 版本选择 / 版本设置）→ 逐条目退场：
///   50ms 淡出 + 50ms 左移 6pt，整列共用 70ms 的错峰窗口
///   （`Delay = 70 / Controls.Count * Id`）。
/// - 没有（启动 / 任务管理 / 联机）→ 整块退场：
///   110ms 缩到 0.95（AniEaseInFluent(Weak)，即 t²），同时 80ms 淡出、延迟 30ms。
enum SidebarExit {
    /// 逐条目退场：单条目淡出时长。
    static var duration: Double { 0.05 * PageAnimationDebug.factor }
    /// 逐条目退场：整列错峰窗口（PCL2 的 70ms）。
    static var window: Double { 0.07 * PageAnimationDebug.factor }
    /// 逐条目退场：左移距离。
    static let offset: CGFloat = -6

    /// 第 index 个条目（共 count 个）的延迟。
    static func delay(for index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        let clamped: Int = min(max(index, 0), count)
        return window * Double(clamped) / Double(count)
    }

    /// 整块退场：缩放时长（PCL2 的 110ms）。
    static var scaleDuration: Double { 0.11 * PageAnimationDebug.factor }
    /// 整块退场：缩放目标。
    static let scaleTarget: CGFloat = 0.95
    /// 整块退场：淡出时长与延迟（PCL2 的 80ms / 30ms）。
    static var fadeDuration: Double { 0.08 * PageAnimationDebug.factor }
    static var fadeDelay: Double { 0.03 * PageAnimationDebug.factor }
}

/// 左下角弹出提示的退场。
///
/// 对应 PCL2 的 ModMain 里 `AniStart({"Hint Hide " & Uuid})` 那一组（PanHint 里的 Border），
/// 不是 MyHint——MyHint 是页面里的提示条，两者的退场不一样：
///
///   · 200ms 左移 50pt，AniEaseInFluent(Middle) = t³
///   · 150ms 淡出，**线性**
///   · 高度收 0，100ms，AniEaseOutFluent(Middle) = 1-(1-t)³
///   · 三条都跑完（最大 200ms）后才从 PanHint 里摘掉
enum HintExit {
    /// 左移时长与距离。
    static var slideDuration: Double { 0.2 * PageAnimationDebug.factor }
    static let slideOffset: CGFloat = -50
    /// 淡出时长（PCL2 没给 Ease，走的是线性）。
    static var fadeDuration: Double { 0.15 * PageAnimationDebug.factor }
    /// 高度收起的时长。
    static var collapseDuration: Double { 0.1 * PageAnimationDebug.factor }
    /// 提示条高度。
    static let height: CGFloat = 22

    /// 从开始退场到可以从列表里删掉的总时长。
    static var window: Double { max(slideDuration, fadeDuration) }

    /// AniEaseInFluent(Middle) = t³，用标准的三次贝塞尔近似。
    static var slideAnimation: Animation {
        .timingCurve(0.32, 0, 0.67, 0, duration: slideDuration)
    }

    static var fadeAnimation: Animation {
        .linear(duration: fadeDuration)
    }

    static var collapseAnimation: Animation {
        .timingCurve(0.33, 1, 0.68, 1, duration: collapseDuration)
    }
}

/// 退场时控件自己算出来的样子：线性淡出 + 线性位移。
///
/// 和 PageEntranceShape 一样是 Animatable：外部只推一条线性动画，
/// 位移与透明度在这里逐帧算——PCL2 的两条 Aa 本来就是各走各的线性插值。
struct ControlExitShape: ViewModifier, Animatable {
    var progress: Double
    /// 退场时的位移方向与距离。
    let offset: CGSize
    /// 关掉时完全不参与（拖自定义主题滑杆重建视图树时用）。
    let enabled: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t: Double = enabled ? min(max(progress, 0), 1) : 0
        content
            .opacity(1 - t)
            .offset(x: offset.width * CGFloat(t), y: offset.height * CGFloat(t))
    }
}

/// 侧边栏整块退场：缩放与淡出时长不同，用一条线性进度分别换算。
struct SidebarScaleExitShape: ViewModifier, Animatable {
    var progress: Double
    let enabled: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let elapsed: Double = min(max(progress, 0), 1) * SidebarExit.scaleDuration
        let scaleT: Double = min(max(elapsed / SidebarExit.scaleDuration, 0), 1)
        let fadeT: Double = min(max((elapsed - SidebarExit.fadeDelay) / SidebarExit.fadeDuration, 0), 1)
        content
            // AniEaseInFluent(Weak)：t²。
            .scaleEffect(
                enabled ? 1 - (1 - SidebarExit.scaleTarget) * CGFloat(scaleT * scaleT) : 1,
                anchor: .center
            )
            .opacity(enabled ? 1 - fadeT : 1)
    }
}
