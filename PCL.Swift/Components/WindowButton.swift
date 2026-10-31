//
//  WindowButton.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/27.
//

import SwiftUI

struct WindowButton: View {
    /// 观察配置：标题栏切到「液态玻璃」时它是浅色的，图标要换成深色。
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var hovered: Bool = false
    private let icon: ImageResource
    private let action: () -> Void

    private var foregroundColor: Color {
        LauncherConfig.shared.navigationBarBackground == .liquidGlass ? .color1 : .white
    }
    
    init(_ icon: ImageResource, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        ZStack {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(.top, 3)
                .foregroundStyle(foregroundColor)
            Circle()
                .fill(foregroundColor.opacity(hovered ? 0.15 : 0))
                .frame(width: hovered ? 30 : 20)
        }
        .animation(.spring(response: 0.2), value: hovered)
        .frame(width: 30, height: 30)
        .contentShape(.rect)
        .onHover { isHovered in
            self.hovered = isHovered
        }
        .onTapGesture(perform: action)
    }
}
