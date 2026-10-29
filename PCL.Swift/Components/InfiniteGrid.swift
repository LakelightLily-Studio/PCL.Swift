//
//  InfiniteGrid.swift
//  PCL.Swift
//
//  无限平铺的纯网格：只画横竖线，不画对角线。
//  线距固定，窗口变大时向四周补线而不是把已有网格拉伸。
//

import SwiftUI

struct InfiniteGrid: View {
    let lineColor: Color
    var spacing: CGFloat = 64
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            guard spacing > 0, size.width > 0, size.height > 0 else { return }

            var path: Path = .init()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
