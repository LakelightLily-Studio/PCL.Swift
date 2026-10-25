//
//  MyCard.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/4.
//

import SwiftUI

/// 卡片。
///
/// 只有一层泛型参数 Content：右上角的 action 用一个轻量类型擦除包装。
///
/// 早先是 MyCard<Content, Action> 两层泛型，而全项目 68 处调用里只有 1 处
/// 真的传了 action——其余 67 处都在为不存在的 Action 付出泛型实例化代价
/// （采样里 MyCard.body.getter 与 swift::MetadataCacheKey 的高占比来自这里）。
struct MyCard<Content: View>: View {
    @Environment(\.cardIndex) private var index: Int
    @Environment(\.disableCardAppearAnimation) private var disableCardAppearAnimation: Bool
    @Environment(\.disableHoverAnimation) private var disableHoverAnimation: Bool
    @EnvironmentObject private var interactionState: CardInteractionState

    /// 下移出现动画变量。
    @State private var appeared: Bool = false
    /// 入场动画是否已完成（完成前不播悬停动画）。
    @State private var appearFinished: Bool = false
    /// 卡片是否已被折叠。
    @State private var folded: Bool = true
    /// 是否被鼠标悬停。
    @State private var hovered: Bool = false
    /// 是否显示鼠标悬停样式，用于避免动画冲突。
    @State private var showHovered: Bool = false
    /// 是否显示卡片内容，在被折叠时为 false。
    @State private var showContent: Bool = false
    /// content() 的实际高度。
    @State private var actualContentHeight: CGFloat = 0
    /// content() 的高度限制。
    @State private var contentHeightLimit: CGFloat? = nil
    @State private var foldWorkItem: DispatchWorkItem?

    private let title: String
    private let foldable: Bool
    private let initialFolded: Bool
    private let titled: Bool
    private let padding: CGFloat
    private let content: () -> Content
    private let action: (() -> AnyView)?

    /// 创建一个卡片视图。
    /// - Parameters:
    ///   - title: 卡片的标题，为 nil 时没有标题栏且不可折叠。
    ///   - foldable: 卡片是否可被折叠。
    ///   - folded: 卡片的初始折叠状态，为 nil 时根据是否可折叠决定。
    ///   - padding: 卡片的内边距。
    ///   - content: 卡片内容。
    init(
        _ title: String?,
        foldable: Bool = true,
        folded: Bool? = nil,
        padding: CGFloat = 18,
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        self.title = title ?? ""
        self.titled = title != nil
        self.foldable = foldable && titled
        self.initialFolded = folded ?? self.foldable
        self.padding = padding
        self.content = content
        self.action = nil
        // 折叠状态在 init 里就位，而不是等到 onAppear：
        // 首帧如果还按"展开"布局，进入页面时会看到卡片内容整个弹开再收回。
        self._folded = .init(initialValue: self.initialFolded)
        self._showContent = .init(initialValue: !self.initialFolded)
        self._contentHeightLimit = .init(initialValue: self.initialFolded ? 0 : nil)
    }

    /// 带右上角操作的卡片。
    ///
    /// action 会被包成 AnyView。这层擦除的代价只在真的用到 action 的那一处
    /// 发生，而不是全部调用点。
    init<Action: View>(
        _ title: String?,
        foldable: Bool = true,
        folded: Bool? = nil,
        padding: CGFloat = 18,
        @ViewBuilder _ content: @escaping () -> Content,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.title = title ?? ""
        self.titled = title != nil
        self.foldable = foldable && titled
        self.initialFolded = folded ?? self.foldable
        self.padding = padding
        self.content = content
        self.action = { AnyView(action()) }
        self._folded = .init(initialValue: self.initialFolded)
        self._showContent = .init(initialValue: !self.initialFolded)
        self._contentHeightLimit = .init(initialValue: self.initialFolded ? 0 : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            if titled {
                HStack {
                    Text(title)
                        .font(.custom("PingFangSC-Semibold", size: 14))
                    Spacer()
                    if foldable {
                        Image(.btnFold)
                            .resizable()
                            .frame(width: 10, height: 6)
                            .rotationEffect(.degrees(folded ? 0 : -180), anchor: .center)
                            // PCL2 的箭头是 250ms 的 easeOutFluent(ExtraStrong)。
                            .animation(CardFold.arrowRotation, value: folded)
                    } else if let action {
                        action()
                    }
                }
                .foregroundStyle(appearFinished && !disableHoverAnimation && showHovered ? Color.color2 : .color1)
                .frame(height: 12)
                .padding(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard foldable else { return }
                    self.foldWorkItem?.cancel()
                    interactionState.isTransitioning = true

                    // 目标高度先夹到 1000：内容再长也不该让动画跑几秒。
                    // 动画结束后再把限制放开，交给自然高度。
                    let targetHeight: CGFloat = min(1000, actualContentHeight) + padding
                    if folded {
                        // 展开卡片
                        folded = false
                        showContent = true
                        withAnimation(CardFold.animation(forDelta: targetHeight)) {
                            contentHeightLimit = targetHeight
                        }
                        let duration: Double = CardFold.duration(forDelta: targetHeight)
                        let foldWorkItem: DispatchWorkItem = .init {
                            contentHeightLimit = nil
                            interactionState.isTransitioning = false
                        }
                        self.foldWorkItem = foldWorkItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: foldWorkItem)
                    } else {
                        // 折叠卡片
                        folded = true
                        let startHeight: CGFloat = contentHeightLimit ?? targetHeight
                        contentHeightLimit = startHeight
                        withAnimation(CardFold.animation(forDelta: -startHeight)) {
                            contentHeightLimit = 0
                        }
                        let duration: Double = CardFold.duration(forDelta: -startHeight)
                        let foldWorkItem: DispatchWorkItem = .init {
                            showContent = false
                            interactionState.isTransitioning = false
                        }
                        self.foldWorkItem = foldWorkItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: foldWorkItem)
                    }
                }
            }

            // 内容始终挂载：折叠时只是高度 0 + 透明。
            // 早先折叠后会把它从视图树里摘掉，再点开时需要重建整棵内容树并
            // 重新布局——主页这种上百个文本节点的卡片，那一帧就是明显的「点了没反应」。
            // 保持挂载后，展开只是改高度，动画立刻能开始。
                VStack {
                    content()
                }
                .disableHoverAnimation(!appearFinished)
                // 只有可折叠的卡片才需要测高：它要用 actualContentHeight 算
                // 展开/折叠的目标高度。不可折叠的卡片 showContent 恒为 true，
                // 测量结果从不参与布局——而每个 GeometryReader 都会给这一层
                // 增加一次额外的布局 pass，一页五六张卡就是五六次多余 pass。
                .modifier(CardHeightReader(enabled: foldable, height: $actualContentHeight))
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: !titled ? padding : 0, leading: padding, bottom: padding, trailing: padding))
                .frame(height: contentHeightLimit, alignment: .top)
                .clipped()
                .opacity(showContent ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        // 修饰器链收进一个独立的 ViewModifier：
        // 每个修饰器都会给 Content 外面再套一层泛型类型，
        // 8 层就是 8 层嵌套泛型。MyCard 有 68 个调用点、每处都是不同具体类型，
        // 采样里 MetadataCacheKey / getGenericContext / chkstk 的高占比
        // 正来自这些层层嵌套的泛型实例。收进 modifier 后，
        // 链的深度对调用点不可见，编译器只需为 modifier 生成一份。
        .modifier(CardChrome(
            hovered: $hovered,
            showHovered: $showHovered,
            appeared: $appeared,
            index: index,
            entranceEnabled: !disableCardAppearAnimation,
            interactionState: interactionState
        ))
        .onAppear {
            if disableCardAppearAnimation {
                appeared = true
                appearFinished = true
            } else {
                appeared = true
                let delay: Double = PageEntrance.delay(for: index)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + PageEntrance.duration) {
                    appearFinished = true
                }
            }
        }
    }
}

/// 按需测量内容高度。
///
/// 把 GeometryReader 收进一个修饰器，只在 enabled 时才挂上去：
/// 不可折叠的卡片完全不参与测量，省掉一次布局 pass。
private struct CardHeightReader: ViewModifier {
    let enabled: Bool
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            height = proxy.size.height
                        }
                        .onChange(of: proxy.size) { newSize in
                            // 只有真的变了才写回：入场动画期间尺寸会连续上报，
                            // 每次都派发一次 async 状态写入会额外触发一轮布局。
                            guard abs(height - newSize.height) > 0.5 else { return }
                            let measured: CGFloat = newSize.height
                            DispatchQueue.main.async {
                                height = measured
                            }
                        }
                }
            }
        } else {
            content
        }
    }
}

/// 卡片的外观与悬停状态。
///
/// 把这些修饰器从 MyCard.body 里挪出来，是为了让"泛型嵌套深度"与
/// 调用点的 Content 类型解耦：body 里每多一个 .xxx 修饰器，就多一层
/// ModifiedContent<ModifiedContent<...>>，而 MyCard 有几十个不同的
/// Content 具体类型，每层都要各自做一次元数据查找。
private struct CardChrome: ViewModifier {
    @Binding var hovered: Bool
    @Binding var showHovered: Bool
    @Binding var appeared: Bool
    let index: Int
    let entranceEnabled: Bool
    @ObservedObject var interactionState: CardInteractionState

    func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                guard hovered != isHovered else { return }
                hovered = isHovered
                if !interactionState.isTransitioning || !isHovered {
                    showHovered = isHovered
                }
            }
            .onChange(of: interactionState.isTransitioning) { newValue in
                if newValue == true || showHovered == hovered { return }
                showHovered = hovered
            }
            .background {
                RoundedRectangle(cornerRadius: 5)
                    // PCL2 的卡片底色是 Color.FromArgb(245, 255, 255, 255)：
                    // 近白、不是灰色。用 colorGray8(#f5f5f5) 在偏蓝的页面底色上
                    // 会显得发灰、和背景糊在一起。
                    .fill(Color.white.opacity(245.0 / 255.0))
                    // 阴影参数对齐 PCL2 的 MyCard + MyDropShadow：
                    // 半径 3；静止用 ColorObject1（这里的 color1，#343d4a）+ 0.07，
                    // 悬停换成 ColorObject4（这里的 color4，主题亮色）+ 0.4。
                    // 之前误用了 color3（主色）和黑色，悬停时边缘的蓝色太浓。
                    .shadow(
                        color: showHovered ? Color.color4.opacity(0.4) : Color.color1.opacity(0.07),
                        radius: 3
                    )
            }
            // 入场动画统一走 PageEntrance（对齐 PCL2 的页面切换动画）。
            .modifier(PageEntranceShape(progress: appeared ? 1 : 0, enabled: entranceEnabled))
            .animation(entranceEnabled ? PageEntrance.animation(for: index) : nil, value: appeared)
            // 悬停的 90ms 与 PCL2 的 MyCard_MouseEnter/MouseLeave 一致。
            .animation(CardFold.hover, value: showHovered)
    }
}
