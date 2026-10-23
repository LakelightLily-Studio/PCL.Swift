//
//  Sidebar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/9.
//

import SwiftUI

protocol Sidebar: View {
    var width: CGFloat { get }
}

struct EmptySidebar: Sidebar {
    /// 侧边栏宽度常量。容器需要在不构造实例的前提下取宽度。
    static let widthConstant: CGFloat = 0

    let width: CGFloat = 0
    
    var body: some View {
        EmptyView()
    }
}
