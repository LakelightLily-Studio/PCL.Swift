//
//  MyTip.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/2/13.
//

import SwiftUI

/// 页面里的横幅提示条（PCL2 的 MyHint）。
///
/// 它在 PCL2 里是**页面级动画控件**：MyPageRight.GetAllAnimControls 会把它和卡片一起编号，
/// 入场 25ms 一格往后错、退场 15ms 一格往后错。所以这里和 MyCard 用同一条时间线
/// （PageEntrance / PageExit + .cardIndex(n)），不再是一块静止的色条。
///
/// 卡片**内部**的提示条不参与：PCL2 的遍历遇到 MyCard 就停了，卡片里的内容跟着卡片动。
struct MyTip: View {
    @Environment(\.cardIndex) private var index: Int
    @Environment(\.disableCardAppearAnimation) private var disableCardAppearAnimation: Bool
    @Environment(\.pageExiting) private var pageExiting: Bool
    @Environment(\.isInsideCard) private var isInsideCard: Bool

    @State private var appeared: Bool = false

    private let text: String
    private let theme: Theme

    init(text: String, theme: Theme) {
        self.text = text
        self.theme = theme
    }

    /// 是否作为页面级控件参与入场 / 退场。
    private var animates: Bool {
        !isInsideCard && !disableCardAppearAnimation
    }

    var body: some View {
        bar
            .modifier(PageEntranceShape(progress: appeared ? 1 : 0, enabled: animates))
            .animation(animates ? PageEntrance.animation(for: index) : nil, value: appeared)
            // 退场与卡片一致：70ms 线性淡出 + 上移 6pt，按同一套序号错峰 15ms。
            .modifier(ControlExitShape(
                progress: pageExiting ? 1 : 0,
                offset: CGSize(width: 0, height: PageExit.offset),
                enabled: animates
            ))
            .animation(animates ? PageExit.animation(for: index) : nil, value: pageExiting)
            .onAppear { appeared = true }
    }

    private var bar: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.borderColor)
                .frame(width: 3)
            MyText(text, color: theme.foregroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            Spacer(minLength: 0)
        }
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .fixedSize(horizontal: false, vertical: true)
    }

    enum Theme {
        case blue, red, yellow

        var borderColor: Color {
            let hex: UInt = switch self {
            case .blue: 0x1172D4
            case .red: 0xD82929
            case .yellow: 0xF57A00
            }
            return .init(hex)
        }

        /// 提示条是浅色系（浅底 + 深字），深色外观下要整块翻过来，
        /// 否则一条亮蓝色横幅会像贴纸一样糊在深色页面上。
        var backgroundColor: Color {
            if Color.isDark {
                let hex: UInt = switch self {
                case .blue: 0x10283D
                case .red: 0x3A1618
                case .yellow: 0x3A2A12
                }
                return .init(hex)
            }
            let hex: UInt = switch self {
            case .blue: 0xD9ECFF
            case .red: 0xFFDDDF
            case .yellow: 0xFFEBD7
            }
            return .init(hex)
        }

        var foregroundColor: Color {
            if Color.isDark {
                let hex: UInt = switch self {
                case .blue: 0x8FC2EE
                case .red: 0xF09090
                case .yellow: 0xF0B574
                }
                return .init(hex)
            }
            let hex: UInt = switch self {
            case .blue: 0x0F64B8
            case .red: 0xBF0B0B
            case .yellow: 0xD86C00
            }
            return .init(hex)
        }
    }
}

#Preview {
    VStack {
        MyTip(text: "Test", theme: .red)
        MyTip(text: "Test", theme: .yellow)
        MyTip(text: "Test", theme: .blue)
    }
    .padding()
}
