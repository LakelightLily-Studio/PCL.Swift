//
//  BackgroundImageView.swift
//  PCL.Swift
//
//  窗口背景图片层，对齐 PCL2 的 FormMain.ImgBack。
//

import SwiftUI
import AppKit
import Core

/// 内容区的背景图片。
///
/// 挂在标题栏以下的最底层：卡片与侧边栏画在它上面，所以卡片会透出一点点图片
/// （PCL2 的卡片底色同样是 245/255 的近白，效果一致）。
/// 不透明度、模糊与自适应方式都读 LauncherConfig，改设置立即生效。
struct BackgroundImageView: View {
    @ObservedObject private var manager: BackgroundImageManager = .shared
    @ObservedObject private var config: LauncherConfigObserver = .shared

    var body: some View {
        GeometryReader { proxy in
            if let image = manager.image {
                layer(image: image, size: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // 模糊会在边缘采样到透明像素，必须把整层放大一点，让衰减落在可视区外，
                    // 否则四边会透出底下的页面底色（「四周掺了一圈糊掉的原背景」）。
                    //
                    // **用 scaleEffect，不要用负内边距**：负内边距会让内容在自己的小盒子里
                    // 居中，原点跑到 (-x, -x)，模糊一开整张图就明显往左上偏。
                    .scaleEffect(blurScale(in: proxy.size), anchor: .center)
                    .blur(radius: CGFloat(blurRadius))
                    .opacity(Double(LauncherConfig.shared.backgroundImageOpacity) / 1000)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        // 换图时淡入，避免整块页面闪一下。
        .animation(.easeOut(duration: 0.2), value: manager.fileURL)
    }

    private var blurRadius: Int {
        min(max(LauncherConfig.shared.backgroundImageBlur, 0), 40)
    }

    /// 模糊时把整层放大的倍率。
    ///
    /// 模糊的衰减范围约 2 倍半径，短边要长出 4 倍半径才能把透明边完全推出可视区；
    /// 上限 1.5，免得半径拉满时整张图被放得太大。
    private func blurScale(in size: CGSize) -> CGFloat {
        let radius: CGFloat = CGFloat(blurRadius)
        guard radius > 0 else { return 1 }
        let shorter: CGFloat = max(min(size.width, size.height), 1)
        return min(1 + 4 * radius / shorter, 1.5)
    }

    @ViewBuilder
    private func layer(image: NSImage, size: CGSize) -> some View {
        switch resolvedSuit(for: image, in: size) {
        case .tile:
            // 平铺：按图片原始尺寸重复，对应 WPF 的 TileMode.Tile。
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .center:
            // 居中：原始尺寸，超出部分裁掉（Stretch.None）。
            Image(nsImage: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .stretch:
            // 拉伸：不保持长宽比，直接填满（Stretch.Fill）。
            Image(nsImage: image)
                .resizable()
        default:
            // 其余都是「保持长宽比铺满 + 某个方向对齐」（Stretch.UniformToFill）。
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height, alignment: resolvedSuit(for: image, in: size).alignment)
                .clipped()
        }
    }

    /// 「自动」的判定与原版一致：图片比窗口的一半还小就平铺，否则保持长宽比铺满。
    private func resolvedSuit(for image: NSImage, in size: CGSize) -> BackgroundImageSuit {
        let suit: BackgroundImageSuit = LauncherConfig.shared.backgroundImageSuit
        guard suit == .automatic else { return suit }
        let isSmall: Bool = image.size.width < size.width / 2 && image.size.height < size.height / 2
        return isSmall ? .tile : .aspectFit
    }
}
