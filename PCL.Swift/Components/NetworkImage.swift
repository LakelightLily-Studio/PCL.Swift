//
//  NetworkImage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/19.
//

import SwiftUI
import Core
import CoreImage

struct NetworkImage: View {
    @State private var nsImage: NSImage = .init(size: .zero)
    private let url: URL
    /// 相对于图片左上角的像素裁剪区域；为 nil 时显示完整图片。
    private let cropRect: CGRect?
    
    init(url: URL, cropRect: CGRect? = nil) {
        self.url = url
        self.cropRect = cropRect
    }
    
    var body: some View {
        imageView
            .task(id: url) {
                do {
                    let data: Data = try await Self.loadData(from: url)
                    let nsImage = try makeImage(from: data)
                    await MainActor.run {
                        withAnimation(nil) {
                            self.nsImage = nsImage
                        }
                    }
                } catch let error where error.isCancellationError {
                } catch {
                    err("加载图片 \(url.absoluteString) 失败：\(error.localizedDescription)")
                }
            }
    }

    @ViewBuilder
    private var imageView: some View {
        if cropRect == nil {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        }
    }

    /// 读取图片数据。
    ///
    /// `file://` 走本地读取：`HTTPClient` 只接受 http/https，演示用的本地图标
    /// 是打包进 App 的文件，不能走它。
    private static func loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        return try await HTTPClient.shared.get(url).data
    }

    private func makeImage(from data: Data) throws -> NSImage {
        guard let cropRect else {
            guard let nsImage: NSImage = .init(data: data) else {
                throw SimpleError("解码 NSImage 失败。")
            }
            return nsImage
        }

        guard let image = CIImage(data: data) else {
            throw SimpleError("解码 CIImage 失败。")
        }

        // Core Image 的原点在左下角，而裁剪区域以图片左上角为原点。
        let extent = image.extent
        let coreImageRect = CGRect(
            x: extent.minX + cropRect.minX,
            y: extent.maxY - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        ).intersection(extent)
        guard !coreImageRect.isNull, coreImageRect.width > 0, coreImageRect.height > 0 else {
            throw SimpleError("图片裁剪区域无效。")
        }

        let cropped = image.cropped(to: coreImageRect)
        guard let cgImage = CIContext().createCGImage(cropped, from: coreImageRect) else {
            throw SimpleError("创建裁剪图片失败。")
        }
        return NSImage(cgImage: cgImage, size: coreImageRect.size)
    }
}
