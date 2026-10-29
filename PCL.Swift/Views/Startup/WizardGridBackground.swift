//
//  WizardGridBackground.swift
//  PCL.Swift
//
//  向导页背景：固定 64pt 线距的无限纯网格（只有横竖线，没有对角线）。
//  开场动画的网格是 5×5 固定分割；向导窗口更大，照搬会被拉大成几根很稀的线，
//  所以这里改成按 64pt 平铺，窗口变大只会补线、不会缩放。
//
//  网格不在向导出现的第一帧就创建：从小窗口拉到大窗口的 0.35s 尺寸动画期间
//  绘制网格会掉帧，所以等尺寸动画结束后再创建，并从顶部向下渐显。
//

import SwiftUI

struct WizardGridBackground: View {
    @ObservedObject private var themeManager: ThemeManager = .shared
    @State private var showGrid: Bool = false
    @State private var reveal: CGFloat = 0

    var body: some View {
        ZStack {
            if showGrid {
                InfiniteGrid(lineColor: Color.color3.opacity(0.10), spacing: 64)
                    .modifier(GridRevealMask(reveal: reveal))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !showGrid else { return }
            Task { @MainActor in
                // 向导在窗口尺寸动画开始后 0.2s 才淡入，尺寸动画本身 0.35s；
                // 再等 0.35s 才创建网格，确保它不会参与尺寸变化的那几帧。
                try? await Task.sleep(seconds: 0.35)
                showGrid = true
                // 先让网格以 reveal = 0 渲染一帧，再启动渐显，避免插入时直接跳到终值。
                try? await Task.sleep(seconds: 0.01)
                withAnimation(.easeOut(duration: 0.8)) {
                    reveal = 1
                }
            }
        }
    }
}

/// 从上到下的渐显遮罩：reveal 从 0 到 1 时，可见区域从顶部推到整张网格。
private struct GridRevealMask: ViewModifier, Animatable {
    var reveal: CGFloat

    var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            Canvas { context, size in
                guard size.height > 0 else { return }

                let fade: CGFloat = size.height * 0.18
                let edge: CGFloat = reveal * (size.height + fade)
                let gradient: Gradient = .init(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, edge - fade) / size.height),
                    .init(color: .clear, location: min(1, edge / size.height))
                ])

                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        gradient,
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}
