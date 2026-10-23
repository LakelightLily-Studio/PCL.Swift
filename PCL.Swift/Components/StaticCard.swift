//
//  StaticCard.swift
//  PCL.Swift
//
//  无交互的静态卡片：没有折叠、没有悬停动画、没有高度测量。
//
//  为什么需要它：MyCard 即使传 foldable: false，仍然挂着
//  @EnvironmentObject、onHover、入场动画的 3 个 DispatchWorkItem、
//  以及一次布局测量。实测单张卡约 6–8ms——一页 5 张卡就是 30ms+。
//  而「关于」「许可声明」这类内容根本不需要任何交互，
//  用轻量版本可以把整页构建时间砍掉一大半。
//

import SwiftUI

struct StaticCard<Content: View>: View {
    @Environment(\.cardIndex) private var index: Int
    @Environment(\.disableCardAppearAnimation) private var disableCardAppearAnimation: Bool

    @State private var appeared: Bool = false

    private let title: String?
    private let padding: CGFloat
    private let content: () -> Content

    init(_ title: String? = nil, padding: CGFloat = 18, @ViewBuilder _ content: @escaping () -> Content) {
        self.title = title
        self.padding = padding
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack {
                    Text(title)
                        .font(.custom("PingFangSC-Semibold", size: 14))
                    Spacer()
                }
                .foregroundStyle(Color.color1)
                .frame(height: 12)
                .padding(12)
            }

            content()
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: title == nil ? padding : 0, leading: padding, bottom: padding, trailing: padding))
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.colorGray8)
                .shadow(color: .black.opacity(0.1), radius: 6)
        }
        .offset(y: appeared ? 0 : -25)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if disableCardAppearAnimation {
                appeared = true
                return
            }
            let delay: Double = Double(min(index, 3)) * 0.04
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { appeared = true }
            }
        }
    }
}
