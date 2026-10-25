//
//  MemoryBar.swift
//  PCL.Swift
//
//  PCL2 的「内存分配」内存条：已使用 / 游戏分配 / 空闲，三段按比例铺满整条。
//  设置 → 启动 与 实例设置 → 内存分配 两处共用，避免各写一份比例计算。
//

import SwiftUI

struct MemoryBar: View {
    let usedGigabytes: Double
    let totalGigabytes: Double
    let gameGigabytes: Double

    var body: some View {
        let total: Double = max(totalGigabytes, 0.1)
        let used: Double = min(usedGigabytes, total)
        let game: Double = max(gameGigabytes, 0)
        // 已用 + 分配可能超过物理内存（小内存机器上自动配置也会保底 0.5 GB），
        // 这时整体等比压缩，避免算出负的"空闲"段。
        let scale: Double = (used + game) > total ? total / (used + game) : 1
        let usedFraction: CGFloat = CGFloat(used * scale / total)
        let gameFraction: CGFloat = CGFloat(game * scale / total)

        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Color.color3, Color.color2], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max((proxy.size.width - 4) * usedFraction, 0))
                    Rectangle()
                        .fill(Color.color3.opacity(0.45))
                        .frame(width: max((proxy.size.width - 4) * gameFraction, 0))
                    Rectangle()
                        .fill(Color.colorGray6.opacity(0.7))
                }
            }
            .frame(height: 5)

            HStack {
                MyText(String(format: "已使用 %.1f / %.1f GB", used, total), size: 11, color: .colorGray3)
                Spacer()
                MyText(String(format: "游戏分配 %.1f GB", game), size: 11, color: .colorGray3)
            }
        }
    }
}
