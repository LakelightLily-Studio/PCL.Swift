//
//  MyTextField.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/2.
//

import SwiftUI

struct MyTextField: View {
    @Binding private var text: String
    @State private var hovered: Bool = false
    @FocusState private var focused: Bool
    private let placeholder: String
    private let secure: Bool

    init(text: Binding<String>, placeholder: String = "", secure: Bool = false) {
        self._text = text
        self.placeholder = placeholder
        self.secure = secure
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Group {
                if secure {
                    SecureField("", text: _text)
                } else {
                    TextField("", text: _text)
                }
            }
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 6)
            .foregroundStyle(Color.color1)
            .onSubmit {
                focused = false
            }

            if !focused && text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Color.colorGray3)
                    .padding(.horizontal, 6)
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(foregroundColor, lineWidth: 1.5, antialiased: false)
                .allowsHitTesting(false)
        }
        .onHover { hovered = $0 }
        .animation(.linear(duration: 0.1), value: hovered)
        .animation(.linear(duration: 0.1), value: focused)
        .onChange(of: text) { newValue in
            if newValue.contains("\n") {
                self.text = newValue.replacingOccurrences(of: "\n", with: "")
            }
        }
        .background(backgroundColor)
        .frame(height: 26)
        .onChange(of: focused) { isFocused in
            if isFocused {
                FocusedTextField.shared.beginTracking { focused = false }
            } else {
                FocusedTextField.shared.endTracking()
            }
        }
        .onDisappear {
            FocusedTextField.shared.endTracking()
        }
    }

    private var foregroundColor: Color {
        if focused { return .color3 }
        if hovered { return .color4 }
        return .color5
    }

    private var backgroundColor: Color {
        if focused || hovered { return .color7 }
        return .cardBackground.opacity(0.5)
    }
}

/// 全局共享的「点击别处失焦」监视器。
///
/// 为什么用事件监视器而不是背景点击手势：手势会被上层视图（卡片、滚动容器）
/// 抢先吃掉，点卡片空白处时根本收不到。
///
/// 为什么是共享单例而不是每个输入框各注册一个：同一时刻最多只有一个输入框
/// 拥有焦点，一页十几个输入框各挂一个全局监视器的话，每次鼠标点击都会被
/// 十几个回调各走一遍 hitTest 向上遍历——这是设置页卡顿的来源之一。
@MainActor
final class FocusedTextField {
    static let shared: FocusedTextField = .init()

    private var monitor: Any?
    private var resign: (() -> Void)?

    private init() {}

    func beginTracking(_ resign: @escaping () -> Void) {
        self.resign = resign
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // 点到别的输入框时放行：那个框会自己接管焦点，不必在这里抢。
            if let hitView = event.window?.contentView?.hitTest(event.locationInWindow) {
                var current: NSView? = hitView
                while let view = current {
                    if view is NSTextField || view is NSTextView {
                        return event
                    }
                    current = view.superview
                }
            }
            let resign = self.resign
            DispatchQueue.main.async {
                resign?()
            }
            return event
        }
    }

    func endTracking() {
        resign = nil
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
