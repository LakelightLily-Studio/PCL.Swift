//
//  PlayerAvatar.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/18.
//

import SwiftUI
import Core

struct PlayerAvatar: View {
    @StateObject private var viewModel: AccountViewModel = .init()
    /// 解码后的皮肤图层。
    ///
    /// 存 NSImage 而不是 CIImage：CIImage 是"处理指令"而非位图，
    /// 每次渲染都要重新执行整条滤镜链。早先连 CIContext 都在 init 里新建，
    /// 而 CIContext 是 GPU 上下文，创建一次是毫秒级操作——
    /// 它出现在 body 求值路径上，就是切页/滚动卡顿的直接来源。
    @State private var headImage: NSImage?
    @State private var bodyImage: NSImage?
    private let account: Account
    private let length: CGFloat

    init(_ account: Account, length: CGFloat = 58) {
        self.account = account
        self.length = length
    }

    var body: some View {
        ZStack {
            if let bodyImage {
                Image(nsImage: bodyImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: length / 10 * 9)
                if let headImage {
                    Image(nsImage: headImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: length)
                }
            }
        }
        .shadow(radius: 2)
        .frame(width: length, height: length)
        .task(id: account.id) {
            // 已经切好图就不用再跑一遍：切页会重建视图，但 .task 的 id 没变。
            guard headImage == nil else { return }
            let skinData: Data = await viewModel.skinData(for: account)
            guard let layers = Self.cropSkin(skinData) else { return }
            await MainActor.run {
                self.headImage = layers.head
                self.bodyImage = layers.body
            }
        }
    }

    /// 把皮肤图切成头与身体两层。
    ///
    /// 只在任务里跑一次，不在 body 求值路径上。CIContext 用共享实例：
    /// 它内部持有 GPU 管线，每个头像各建一个会瞬间吃满资源。
    private static func cropSkin(_ data: Data) -> (head: NSImage, body: NSImage)? {
        guard let image = CIImage(data: data) else {
            err("加载 CIImage 失败")
            return nil
        }
        let yOffset: CGFloat = image.extent.height == 32 ? 0 : 32
        let context: CIContext = Self.sharedContext

        func crop(startX: CGFloat, startY: CGFloat) -> NSImage? {
            let rect: CGRect = .init(x: startX, y: startY + yOffset, width: 8, height: 8)
            let cropped: CIImage = image.cropped(to: rect)
            guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
                warn("创建 CGImage 失败")
                return nil
            }
            return NSImage(cgImage: cgImage, size: rect.size)
        }

        guard let head = crop(startX: 40, startY: 16),
              let body = crop(startX: 8, startY: 16) else {
            return nil
        }
        return (head, body)
    }

    /// 共享的 CIContext。创建成本高（GPU 管线 + 内核编译），进程内共用一个即可。
    private static let sharedContext: CIContext = .init()
}
