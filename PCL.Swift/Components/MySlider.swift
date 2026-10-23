//
//  MySlider.swift
//  PCL.Swift
//
//  自绘滑杆。原生 Slider 与项目其余控件的描边/配色风格不一致，
//  且没有"拖动时高亮"的统一观感，所以这里按 MyButton 的语言重画一条。
//

import SwiftUI

struct MySlider: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?

    @State private var hovered: Bool = false
    @State private var dragging: Bool = false
    /// 拖动期间的本地值。拖动时只更新它，松手才写回 Binding：
    /// 直接写回会让上层 @Published 变化，进而重建本视图、销毁手势。
    @State private var dragValue: Double?

    init(value: Binding<Double>, range: ClosedRange<Double>, step: Double? = nil) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        GeometryReader { proxy in
            let width: CGFloat = proxy.size.width
            let knobSize: CGFloat = 14
            let usableWidth: CGFloat = max(width - knobSize, 1)
            let progress: CGFloat = CGFloat(normalized(for: dragValue ?? value))
            let knobX: CGFloat = usableWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.colorGray6)
                    .frame(height: 4)
                Capsule()
                    .fill(accentColor)
                    .frame(width: knobX + knobSize / 2, height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Circle()
                            .strokeBorder(accentColor, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 2)
                    .offset(x: knobX)
            }
            .frame(height: knobSize)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        let x: CGFloat = gesture.location.x - knobSize / 2
                        let ratio: Double = Double(min(max(x / usableWidth, 0), 1))
                        let newValue: Double = clampedValue(for: ratio)
                        dragValue = newValue
                        value = newValue
                    }
                    .onEnded { _ in
                        dragging = false
                        if let dragValue {
                            value = dragValue
                        }
                        dragValue = nil
                    }
            )
            .onHover { hovered = $0 }
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }

    private func normalized(for rawValue: Double) -> Double {
        let span: Double = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((rawValue - range.lowerBound) / span, 0), 1)
    }

    private var accentColor: Color {
        dragging ? .color2 : (hovered ? .color3 : .color4)
    }

    private func clampedValue(for ratio: Double) -> Double {
        var newValue: Double = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            newValue = (newValue / step).rounded() * step
        }
        // 夹一次：ratio 已被夹住，但 step 取整可能把它推出区间。
        return min(max(newValue, range.lowerBound), range.upperBound)
    }
}
