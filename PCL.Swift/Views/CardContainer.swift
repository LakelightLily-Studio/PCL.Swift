//
//  CardContainer.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/7.
//

import SwiftUI

/// 页面滚动容器。
///
/// 用 @StateObject 持有 interactionState 是为了让整页卡片共享同一个"折叠动画
/// 进行中"标记——但 @StateObject 的生命周期绑定在视图身份上，切页时容器重建，
/// 这个对象也就换了一个，所有 MyCard 的 @EnvironmentObject 订阅全部失效重连。
///
/// 现在改成进程内共享单例：它只是一个"是否有卡片正在折叠"的瞬时标记，
/// 没有页面私有的语义，跨页复用完全安全，还省掉每次切页的一轮订阅重连。
struct CardContainer<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // 间距与内边距对齐 PCL2 的 MyPageRight：卡片之间 15、内容区四周 25。
            VStack(spacing: 15) {
                content()
            }
            .frame(maxWidth: .infinity)
            .padding(25)
        }
        .environmentObject(CardInteractionState.shared)
    }
}

class CardInteractionState: ObservableObject {
    static let shared: CardInteractionState = .init()

    @Published private var value = false
    private let isStatic: Bool

    init(isStatic: Bool = false) {
        self.isStatic = isStatic
    }

    var isTransitioning: Bool {
        get { isStatic ? false : value }
        set {
            if !isStatic { value = newValue }
        }
    }
}
