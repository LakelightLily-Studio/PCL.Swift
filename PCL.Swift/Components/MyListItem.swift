//
//  MyListItem.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/5.
//

import SwiftUI

struct MyListItem<Content: View>: View {
    @State private var hovered: Bool = false
    @State private var backgroundScale: CGFloat = 0.92
    private let content: (Bool) -> Content
    
    init(_ content: @escaping (Bool) -> Content) {
        self.content = content
    }
    
    init(_ content: @escaping () -> Content) {
        self.init({ _ in content() })
    }
    
    init(_ model: ListItem, selected: Bool = false) where Content == AnyView {
        self.init {
            AnyView(
                HStack(spacing: 0) {
                    if selected {
                        RightRoundedRectangle(cornerRadius: 2)
                            .fill(Color.color3)
                            .frame(width: 4, height: 24)
                            .offset(x: -4)
                    }
                    // 显式 center：默认也是 center，但这里写出来是为了说明意图——
                    // 图标与右侧文字块按几何中心对齐，单行与双行文字的条目视觉高度才一致。
                    HStack(alignment: .center, spacing: 0) {
                        if let image = model.image {
                            image.makeView()
                            .scaledToFit()
                            .frame(width: model.imageSize, height: model.imageSize)
                            .foregroundStyle(Color.color1)
                            .padding(.trailing, 6)
                        }
                        // 主标题与灰色副标题之间留 2pt：默认 0 行距会让两行贴在一起，
                        // 字号不同时尤其显得挤，与右侧留白不成比例。
                        VStack(alignment: .leading, spacing: 2) {
                            MyText(model.name)
                                .lineLimit(1)
                            if let description = model.description {
                                MyText(description, color: .colorGray3)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
            )
        }
    }
    
    var body: some View {
        content(hovered)
            .frame(maxWidth: .infinity)
            .padding(4)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovered ? Color.color2.opacity(0.1) : .clear)
                    .scaleEffect(backgroundScale)
                    .allowsHitTesting(false)
            }
            .onHover { hovered in
                withAnimation(.spring(response: 0.2)) {
                    self.hovered = hovered
                    if hovered {
                        backgroundScale = 1
                    } else {
                        backgroundScale = 0.92
                    }
                }
            }
    }
}

struct ListItemButton: View {
    @State private var pressed: Bool = false
    private let icon: ListItem.Image
    private let scale: Double
    private let clickPerform: () -> Void
    
    init(_ icon: ListItem.Image, scale: Double = 1.0, clickPerform: @escaping () -> Void) {
        self.icon = icon
        self.scale = scale
        self.clickPerform = clickPerform
    }
    
    var body: some View {
        icon.makeView()
            .scaledToFit()
            .frame(height: 16)
            .foregroundStyle(Color.color3)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        pressed = true
                    }
                    .onEnded { _ in
                        clickPerform()
                        pressed = false
                    }
            )
            .scaleEffect((pressed ? 0.8 : 1.0) * scale)
            .animation(.spring(response: 0.2), value: pressed)
    }
}

#Preview {
    MyListItem(.init(name: "Test", description: "lorem ipsum dolor sit amet consectetur"))
    .frame(width: 400, height: 50)
    .padding()
    .background(.white)
}
