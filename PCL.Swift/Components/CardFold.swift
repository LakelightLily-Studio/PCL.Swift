//
//  CardFold.swift
//  PCL.Swift
//
//  可折叠卡片（下拉卡片）动画与时序参数，大小取自 PCL2 的
//  MyCard.StartHeightAnimation（Controls/MyCard.vb 第 176–236 行）：
//
//    · |Δ| ≤ 800        ：150ms，AniEaseOutFluent(ExtraStrong)，即 1-(1-t)^5
//    · 收缩且 |Δ| > 500  ：100ms 匀速段 + 150ms 减速段（共 0.25s）
//    · 展开且 Δ > 3000   ：300ms 匀速段（5000px/s）+ 400ms 减速段（共 0.7s）
//    · 其余              ：匀速到剩 150px，再 200ms 减速
//
//  PCL2 的动画是"匀速段 + 带初速度的减速段"两条叠加，SwiftUI 的 .animation
//  只能挂一条曲线，所以这里保留时长、用起始斜率很高的 cubic-bezier 近似形状。
//  想要逐帧完全一致得另写 Animatable 修饰器，当前不这么做。
//

import SwiftUI

enum CardFold {
    /// 展开/收缩的动画时长。
    static func duration(forDelta delta: CGFloat) -> Double {
        let magnitude: CGFloat = abs(delta)
        if magnitude <= 800 { return 0.15 }
        if delta > 0 {
            // 展开：超过 3000 需要匀速段，否则只留 150px 减速。
            return magnitude > 3000 ? 0.7 : Double(magnitude - 150) / 4000 + 0.2
        }
        // 收缩：超过 500 就强制 100ms 匀速 + 150ms 减速，避免高卡片收得太磨蹭。
        return magnitude > 500 ? 0.25 : Double(magnitude - 150) / 4000 + 0.2
    }

    /// 高度动画本身。
    static func animation(forDelta delta: CGFloat) -> Animation {
        let duration: Double = duration(forDelta: delta)
        if abs(delta) <= 800 {
            // easeOutQuint，对应 PCL2 的 AniEaseOutFluent(ExtraStrong)。
            return .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        }
        // 带初速度的减速段：起始斜率远高于 1，末段平缓。
        return .timingCurve(0.05, 0.65, 0.2, 1, duration: duration)
    }

    /// 折叠箭头的旋转：PCL2 是 250ms 的 AniEaseOutFluent(ExtraStrong)。
    static let arrowRotation: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.25)

    /// 卡片悬停的阴影与标题色：PCL2 的 MyCard_MouseEnter/MouseLeave 用 90ms。
    static let hover: Animation = .easeOut(duration: 0.09)
}
