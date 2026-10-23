//
//  BackgroundLayer.swift
//  PCL.Swift
//
//  启动器背景图。挂在 ContentView 最底层，标题栏与侧边栏都盖在它上面。
//
//  为什么单独做一个视图：模糊要用 SwiftUI 的 .blur，而 .blur 会把整个
//  视图树离屏渲染一遍。只包住图片本身，其余内容就不会跟着被重绘。
//

import SwiftUI
import Core

struct BackgroundLayer: View {
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    // .high 插值会让每次重绘都走高质量重采样；背景本来就是模糊的，
                    // 用默认插值肉眼无差别。
                    .interpolation(.medium)
                    .aspectRatio(contentMode: LauncherConfig.shared.backgroundFills ? .fill : .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    // drawingGroup 先把图片拍平成一张位图再做模糊：
                    // 否则 blur 会跟着下层视图一起被反复重算，滚动时每帧都做一次
                    // 全屏高斯模糊——这是最贵的一项。
                    .drawingGroup()
                    .blur(radius: LauncherConfig.shared.backgroundBlur)
                    .opacity(LauncherConfig.shared.backgroundOpacity)
                    .overlay {
                        if LauncherConfig.shared.backgroundTinted {
                            Color.colorBackground.opacity(0.35)
                        }
                    }
                    .id(imageIdentity)
            }
        }
        .allowsHitTesting(false)
        .onAppear { load() }
        .onChange(of: LauncherConfig.shared.backgroundImageURL) { _ in load() }
        .onChange(of: configObserver.tick) { _ in load() }
    }

    /// 换图时给 SwiftUI 一个稳定的重建标识：图片内容变了但路径没变时
    /// （用户覆盖了同名文件），只靠 URL 不会触发重绘。
    private var imageIdentity: String {
        "\(LauncherConfig.shared.backgroundImageURL?.path ?? "")-\(image?.size.width ?? 0)"
    }

    /// 已解码的图片缓存，按 URL 索引。
    ///
    /// 主题切换会重建整棵视图树，BackgroundLayer 随之重建并重新读盘 + 解码。
    /// 大图解码是几十毫秒级的操作，每次换主题都做一遍就会明显卡。
    private static var imageCache: [URL: NSImage] = [:]

    private func load() {
        guard let url = LauncherConfig.shared.backgroundImageURL else {
            image = nil
            return
        }
        if let cached = Self.imageCache[url] {
            image = cached
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            warn("背景图片不存在：\(url.path)")
            image = nil
            return
        }
        guard let loaded = NSImage(contentsOf: url) else {
            err("背景图片解码失败：\(url.path)")
            image = nil
            return
        }
        Self.imageCache[url] = loaded
        image = loaded
    }
}
