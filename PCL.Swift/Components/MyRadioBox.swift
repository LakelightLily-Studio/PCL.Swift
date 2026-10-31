//
//  MyRadioBox.swift
//  PCL.Swift
//
//  圆形单选框，对齐 PCL2 的 Controls/MyRadioBox。
//

import SwiftUI

/// 圆形单选框。
///
/// 与 `MyComboBox`（方形复选框）成对使用：**单选组用这个，可多选的开关用那个**。
/// 尺寸、配色与动画都照 PCL2 的 MyRadioBox：
///
/// - 外圈 18pt、描边 1.1、内点 9pt，圈内是 #55ffffff 的半透明白；
/// - 选中时描边换成 ColorBrush2（color2），文字保持 ColorBrush1；
/// - 悬停时描边与文字换成 ColorBrush3（color3），进入 100ms、离开 200ms；
/// - 按下时圈内换成 ColorBrushBg1，未选中时外圈缩到 0.92；
/// - 内点以 150ms × 2.6 的 easeOutBack 弹入，取消时 150ms easeIn 缩回。
///
/// 单选组的互斥不在这里做：调用方各自绑定到同一个枚举，
/// 由 Binding 的 set 拦下「点了已选中项」的情况（与 MyComboBox 的 allowsUncheck 同义）。
struct MyRadioBox: View {
    @Binding private var checked: Bool
    @State private var hovered: Bool = false
    @State private var pressed: Bool = false
    private let text: String
    private let enabled: Bool

    /// 内点弹入：PCL2 的 AnimationTimeOfCheck(150) × 2.6，easeOutBack 末尾带一点过冲。
    private static let checkAnimation: Animation = .timingCurve(0.175, 0.885, 0.32, 1.275, duration: 0.39)
    /// 内点缩回：PCL2 的 150ms easeInFluent。
    private static let uncheckAnimation: Animation = .easeIn(duration: 0.15)
    /// 鼠标进入 100ms、离开 200ms（PCL2 的 AnimationTimeOfMouseIn / AnimationTimeOfMouseOut）。
    private static let hoverIn: Animation = .easeOut(duration: 0.1)
    private static let hoverOut: Animation = .easeOut(duration: 0.2)

    init(checked: Binding<Bool>, text: String, enabled: Bool = true) {
        self._checked = checked
        self.text = text
        self.enabled = enabled
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                // 圈内底色：按下时变 ColorBrushBg1，其余时间是 #55ffffff。
                Circle()
                    .fill(pressed && enabled ? Color.colorBg1 : Color.cardBackground.opacity(0x55 / 255.0))
                Circle()
                    .strokeBorder(strokeColor, lineWidth: 1.1)
                Circle()
                    .fill(strokeColor)
                    .frame(width: 9, height: 9)
                    .scaleEffect(checked ? 1 : 0.001)
                    .opacity(checked ? 1 : 0)
            }
            .frame(width: 18, height: 18)
            // 未选中时按下会把外圈压小一点（PCL2 的 18 → 16.5）。
            .scaleEffect(pressed && !checked && enabled ? 0.92 : 1, anchor: .center)

            MyText(text, size: 13, color: textColor)
        }
        // PCL2 的 ShapeBorder 左边距 1、文字左边距 26：26 - 1 - 18 = 7 的间距。
        .padding(.leading, 1)
        .frame(minWidth: 20, minHeight: 20)
        .fixedSize()
        .contentShape(.rect)
        .onHover { isHovered in
            guard enabled, hovered != isHovered else { return }
            hovered = isHovered
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard enabled, !pressed else { return }
                    pressed = true
                }
                .onEnded { _ in
                    guard enabled else { return }
                    pressed = false
                    // 已选中的项再点一次不应该变成「一个都没选」，
                    // 与 MyComboBox 的单选组用法保持一致。
                    if !checked { checked = true }
                }
        )
        .animation(checked ? Self.checkAnimation : Self.uncheckAnimation, value: checked)
        .animation(hovered ? Self.hoverIn : Self.hoverOut, value: hovered)
        .animation(Self.hoverIn, value: pressed)
        .opacity(enabled ? 1 : 0.6)
    }

    /// 描边与内点的颜色。
    private var strokeColor: Color {
        guard enabled else { return .colorGray5 }
        if hovered { return .color3 }
        return checked ? .color2 : .color1
    }

    /// 文字颜色：悬停时变主色，选中不改（PCL2 的选中态只换描边）。
    private var textColor: Color {
        guard enabled else { return .colorGray5 }
        return hovered ? .color3 : .color1
    }
}

#Preview {
    RadioPreview()
}

private struct RadioPreview: View {
    @State private var selected: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                MyRadioBox(
                    checked: Binding(get: { selected == index }, set: { if $0 { selected = index } }),
                    text: "选项 \(index)"
                )
            }
            MyRadioBox(checked: .constant(true), text: "已禁用", enabled: false)
        }
        .padding()
        .background(.white)
    }
}
