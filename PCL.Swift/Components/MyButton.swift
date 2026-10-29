//
//  MyButton.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/4.
//

import SwiftUI
import Core

/// 按钮。
///
/// 内部拆成两层：
/// - ButtonFace：纯绘制，不持有状态，参数全是值
/// - ButtonInteraction：负责 hover / 按压 / 手势，包在 ButtonFace 外面
///
/// 这样拆的原因是 SwiftUI 的泛型类型元数据开销：原来 body 里 6 个修饰器
/// 直接串在 ZStack 上，每个 MyButton 实例都会生成一条 6 层嵌套的
/// ModifiedContent 类型。设置页有十几个按钮，每页就是十几个独立的
/// 泛型实例，采样里 MetadataCacheKey / getGenericContext 的占比来自这里。
///
/// 拆开之后，ButtonFace 只有一层（ZStack + 少量绘制），
/// 交互那层由 modifier 统一承载，编译器只需为它生成一份代码。
struct MyButton: View {
    @State private var hovered: Bool = false
    @State private var isPressed: Bool = false
    private let label: String
    private let subLabel: String?
    private let textPadding: EdgeInsets
    private let type: MyButtonType
    private let disabled: Bool
    private let action: () -> Void

    init(
        _ label: String,
        subLabel: String? = nil,
        textPadding: EdgeInsets = .init(),
        type: MyButtonType = .normal,
        disabled: Bool = false,
        _ action: @escaping () -> Void
    ) {
        self.label = label
        self.subLabel = subLabel
        self.textPadding = textPadding
        self.type = type
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        ButtonFace(
            label: label,
            subLabel: subLabel,
            textPadding: textPadding,
            type: type,
            hovered: hovered,
            disabled: disabled
        )
        .modifier(ButtonInteraction(
            hovered: $hovered,
            isPressed: $isPressed,
            disabled: disabled,
            action: action
        ))
    }
}

/// 按钮样式。
///
/// 从 MyButton.Type 提出来单独成类型：嵌套在泛型 View 里的枚举会让
/// 每个使用点的类型查找都多绕一层。
enum MyButtonType {
    case normal, highlight, red

    var color: Color {
        switch self {
        case .normal: .color1
        case .highlight: .color2
        case .red: Color(0xCE2111)
        }
    }

    var hoverColor: Color {
        switch self {
        case .normal: .color3
        case .highlight: .color3
        case .red: Color(0xFF4C4C)
        }
    }
}

extension MyButton {
    /// 兼容别名：既有代码里写作 MyButton.Type 的地方继续可用。
    typealias `Type` = MyButtonType
}

/// 按钮的纯绘制部分。不持有状态，参数变化即重绘。
private struct ButtonFace: View {
    let label: String
    let subLabel: String?
    let textPadding: EdgeInsets
    let type: MyButtonType
    let hovered: Bool
    let disabled: Bool

    private var color: Color {
        if disabled { return .colorGray4 }
        return hovered ? type.hoverColor : type.color
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(hovered ? 0.2 : 0.005))
            RoundedRectangle(cornerRadius: 4)
                .stroke(style: .init(lineWidth: 1.2))
                .fill(color)
                .padding(1.2)
                .brightness(hovered ? 0.2 : 0)
            VStack(spacing: 4) {
                MyText(label, color: color)
                    .padding(.horizontal, 10)
                    .padding(textPadding)
                if let subLabel {
                    MyText(subLabel, size: 12, color: .colorGray3)
                }
            }
        }
    }
}

/// 按钮的交互层：hover、按压缩放、点击手势。
private struct ButtonInteraction: ViewModifier {
    @Binding var hovered: Bool
    @Binding var isPressed: Bool
    let disabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: hovered)
            .animation(.easeInOut(duration: 0.2), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { isHovered in
                guard !disabled, hovered != isHovered else { return }
                hovered = isHovered
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !disabled else { return }
                        isPressed = true
                    }
                    .onEnded { _ in
                        guard !disabled else { return }
                        action()
                        isPressed = false
                    }
            )
    }
}

#Preview {
    MyButton("实例选择", type: .highlight) {
        debug("Button pressed")
    }
    .frame(width: 117, height: 32)
    .padding()
    .background(.white)
}
