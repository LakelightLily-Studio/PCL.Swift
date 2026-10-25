//
//  MyTextArea.swift
//  PCL.Swift
//
//  多行文本框。MyTextField 是单行 TextField（还会主动删掉换行），而 JVM 参数
//  那类内容天生要多行：一屏塞不下就得能回车换行，这是 PCL2 里高度 100 的
//  MyTextBox 的对应物。
//
//  样式沿用 MyTextField：同一个描边、同一个悬停/聚焦配色，避免两个输入框
//  长得不像一家人。
//

import SwiftUI

struct MyTextArea: View {
    @Binding private var text: String
    @State private var hovered: Bool = false
    @FocusState private var focused: Bool
    private let placeholder: String
    private let height: CGFloat

    init(text: Binding<String>, placeholder: String = "", height: CGFloat = 96) {
        self._text = text
        self.placeholder = placeholder
        self.height = height
    }

    private var borderColor: Color {
        focused ? .color3 : hovered ? .color2 : .color1
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 12))
                .focused($focused)
                .modifier(TransparentEditorBackground())
                .padding(4)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.colorGray3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: 1.5, antialiased: false)
                .allowsHitTesting(false)
        }
        // 宽度必须显式吃满：TextEditor 没有固有宽度，放在 HStack 里会缩成一条。
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onHover { hovered = $0 }
        .animation(.linear(duration: 0.1), value: hovered)
        .animation(.linear(duration: 0.1), value: focused)
    }
}

/// 去掉 TextEditor 自带的不透明底色。
///
/// `scrollContentBackground` 是 macOS 13 才有的 API，而 App 的部署目标是 12.0，
/// 所以只能在运行时判断；12 上保留系统底色（白），视觉差异可以接受。
private struct TransparentEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}
