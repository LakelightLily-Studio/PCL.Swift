//
//  Overlays.swift
//  PCL.Swift
//
//  窗口级的两个浮层：消息框与提示条。
//
//  原先它们以 private 形式内嵌在 `ContentView` 里，只有进入启动器主体才存在。
//  但首次启动的向导要弹正版账号的设备码、要提示"账号名非法"，那两阶段没有
//  `ContentView`，弹窗与提示就静默丢失了。抽出来后由 `RootView` 按阶段挂载。
//

import SwiftUI
import Core

/// 消息框浮层：遮罩 + 旋转弹入的对话框。
struct MessageBoxOverlay: View {
    @ObservedObject var messageBoxManager: MessageBoxManager = .shared
    @State private var messageBox: MessageBoxModel?

    @State private var opacity: CGFloat = 0
    @State private var rotation: CGFloat = 4
    @State private var offsetY: CGFloat = 40

    @State private var animationHideWorkItem: DispatchWorkItem?

    var body: some View {
        Group {
            if let messageBox {
                ZStack {
                    // 遮罩要铺满整扇窗口（含标题栏区域）：RootView 的内容会遵守顶部安全区，
                    // 而各阶段视图本身都 .ignoresSafeArea()，不忽略的话遮罩顶上会缺一条。
                    Rectangle()
                        .fill(messageBox.level == .error ? Color(0xFF0000).opacity(0.5) : .black.opacity(0.35))
                        .ignoresSafeArea()
                    MessageBoxView(model: messageBox)
                        .rotationEffect(.degrees(rotation))
                        .offset(y: offsetY)
                }
                .opacity(opacity)
            }
        }
        .onChange(of: messageBoxManager.currentMessageBox) { newValue in
            if newValue != nil { // 移入
                animationHideWorkItem?.cancel()
                messageBox = newValue
                withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                    offsetY = 0
                }
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 1
                    rotation = 0
                }
            } else { // 移出
                let workItem: DispatchWorkItem = .init {
                    self.messageBox = nil
                    self.rotation = 4
                    self.offsetY = 40
                }
                animationHideWorkItem = workItem
                let duration: CGFloat = 0.15
                DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
                withAnimation(.easeOut(duration: duration)) {
                    opacity = 0
                    offsetY = 60
                }
                withAnimation(.easeIn(duration: duration)) {
                    rotation = 6
                }
            }
        }
    }
}

/// 提示条浮层：左下角依次滑入的小条。
struct HintOverlay: View {
    @ObservedObject private var hintManager: HintManager = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            ForEach(hintManager.hints) { hint in
                HintView(model: hint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: hintManager.hints)
        .padding(.bottom, 100)
        // 纯展示层，不能吃掉下面的点击。
        .allowsHitTesting(false)
    }
}

private struct HintView: View {
    @State private var appeared: Bool = false
    private let model: HintModel

    init(model: HintModel) {
        self.model = model
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RightRoundedRectangle(cornerRadius: 5)
                .fill(color)
                .frame(height: 22)
            MyText(model.text, color: .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -50)
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(duration: 0.2, bounce: 0), value: appeared)
        .onAppear {
            appeared = true
        }
    }

    private var color: Color {
        switch model.type {
        case .info: Color(0x0A8EFC)
        case .finish: Color(0x1DA01D)
        case .critical: Color(0xFF2B00)
        }
    }
}
