//
//  MyComboBox.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/14.
//

import SwiftUI

struct MyComboBox: View {
    @Binding private var checked: Bool
    @State private var hovered: Bool = false
    @State private var scale: CGFloat = 1.0
    @State private var checkedScale: CGFloat = 0.0
    @State private var canClick: Bool = true
    private let text: String
    /// 是否允许通过点击取消勾选。
    ///
    /// 用于「单选组」：语义上已选中项再点一次不应该变成一个都没选。
    /// 关掉后点击已勾选项不会有任何视觉反馈，动画也不会播放一半再弹回来。
    private let allowsUncheck: Bool

    private let scaleAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.5)

    /// - Parameters:
    ///   - checked: 勾选状态。
    ///   - text: 显示文案。
    ///   - allowsUncheck: 是否允许点击取消勾选，默认允许。
    ///     单选组应传 false：否则点了已选项会先播取消动画，再被绑定的 set 拦下，
    ///     视觉上「闪一下取消」，直到视图重建才恢复。
    init(checked: Binding<Bool>, text: String, allowsUncheck: Bool = true) {
        self._checked = checked
        self.text = text
        self.allowsUncheck = allowsUncheck
    }
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(hovered ? Color.color3 : checked ? .color2 : .color1, lineWidth: 1.1)
                    .frame(width: 18, height: 18)
                    .scaleEffect(scale, anchor: .center)
                
                Image(.iconTaskFinished)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12)
                    .scaleEffect(checkedScale)
                    .foregroundStyle(hovered ? Color.color3 : .color2)
            }
            MyText(text, color: hovered ? .color3 : .color1)
        }
        .frame(minWidth: 20, minHeight: 20)
        .fixedSize()
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .pointingHandCursor() 
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !canClick { return }
                    withAnimation(.spring(duration: 0.3)) {
                        scale = 0.95
                    }
                }
                .onEnded { _ in
                    if !canClick { return }
                    canClick = false
                    withAnimation(.spring(duration: 0.1)) {
                        scale = 0.5
                    }
                    
                    let checked = checked
                    // 单选组：已勾选的项再点一次不应该变成「一个都没选」，
                    // 所以这里直接不写回绑定，只把按压缩放弹回去。
                    if checked && !allowsUncheck {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(scaleAnimation) {
                                scale = 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                canClick = true
                            }
                        }
                        return
                    }
                    self.checked.toggle()
                    
                    if checked {
                        withAnimation(scaleAnimation) {
                            checkedScale = 0
                        }
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(scaleAnimation) {
                            scale = 1
                            if !checked { checkedScale = 1 }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            canClick = true
                        }
                    }
                }
        )
        .animation(.easeInOut(duration: 0.2), value: hovered)
        .animation(scaleAnimation, value: checked)
        .onAppear {
            checkedScale = checked ? 1 : 0
        }
        .onChange(of: checked) { newValue in
            guard canClick else { return }
            withAnimation(scaleAnimation) {
                checkedScale = newValue ? 1 : 0
            }
        }
    }
}

#Preview {
    PreviewView()
}

private struct PreviewView: View {
    @State private var checked: Bool = false
    
    var body: some View {
        MyComboBox(checked: $checked, text: "复选框")
            .padding()
            .background(.white)
    }
}
