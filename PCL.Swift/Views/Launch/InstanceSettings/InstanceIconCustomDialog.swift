//
//  InstanceIconCustomDialog.swift
//  PCL.Swift
//
//  实例图标 →「自定义…」的模态弹窗：从 URL 取图标，或直接挑一张本地图片。
//
//  布局按需求固定：
//    [预览] 自定义图标
//    ────────────────
//    从 URL 获取图标或使用本地图标
//    [ https://example.com           ] [选择本地图片]
//                              [取消] [保存]
//

import SwiftUI
import AppKit
import Core

struct InstanceIconCustomDialog: View {
    @ObservedObject private var viewModel: InstanceOverviewViewModel
    private let onClose: () -> Void

    @State private var text: String = ""
    /// 实时预览：输入框里是图片 URL 或本地文件时显示它，否则显示当前图标。
    @State private var preview: NSImage?
    @State private var saving: Bool = false

    init(viewModel: InstanceOverviewViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                previewView
                    .frame(width: 40, height: 40)
                MyText("自定义图标", size: 23, color: .color2)
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(Color.color2)
                .frame(height: 2)
                .padding(.top, 9)
                .padding(.bottom, 13)

            MyText("从 URL 获取图标或使用本地图标")

            HStack(spacing: 10) {
                MyTextField(text: $text, placeholder: "https://example.com")
                MyButton("选择本地图片") { chooseLocalImage() }
                    .fixedSize()
            }
            .padding(.top, 10)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                MyButton("取消") { onClose() }
                MyButton("保存", type: .highlight, disabled: trimmedText.isEmpty || saving) {
                    save()
                }
            }
            .padding(.top, 18)
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.cardBackground)
        .onAppear {
            preview = viewModel.iconImage ?? NSImage(named: fallbackAssetName)
        }
        // 输入框一变就重新取预览；URL 走网络，本地路径直接读文件。
        .task(id: text) { await refreshPreview() }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 「默认」那张图：按实例的加载器推导，与下拉里的第一项一致。
    private var fallbackAssetName: String {
        switch viewModel.instance.modLoader {
        case .fabric: "iconFabric"
        case .forge: "iconForge"
        case .neoforge: "iconNeoforge"
        case nil: "iconGrassBlock"
        }
    }

    @ViewBuilder
    private var previewView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.colorGray7)
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
            }
        }
    }

    private func refreshPreview() async {
        let input: String = trimmedText
        guard !input.isEmpty else {
            preview = viewModel.iconImage ?? NSImage(named: fallbackAssetName)
            return
        }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http") {
            // 输入框每敲一个字符都会触发，等 0.4s 再发请求。
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let response = try await HTTPClient.shared.get(url, timeout: 15)
                guard (200..<300).contains(response.statusCode), let image = NSImage(data: response.data) else {
                    return
                }
                preview = image
            } catch {
                // 预览失败不打扰用户，保存时再报错。
                debug("预览图标失败：\(error.localizedDescription)")
            }
        } else if FileManager.default.fileExists(atPath: input) {
            preview = NSImage(contentsOfFile: input)
        }
    }

    private func chooseLocalImage() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = "选择图标图片"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            text = url.path
        }
    }

    private func save() {
        let input: String = trimmedText
        guard !input.isEmpty else { return }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http") {
            saving = true
            Task {
                defer { saving = false }
                do {
                    let response = try await HTTPClient.shared.get(url, timeout: 20)
                    guard (200..<300).contains(response.statusCode) else {
                        throw SimpleError("返回 \(response.statusCode)")
                    }
                    guard NSImage(data: response.data) != nil else {
                        throw SimpleError("返回的内容不是图片")
                    }
                    viewModel.setIcon(imageData: response.data)
                    onClose()
                } catch {
                    err("从 URL 设置实例图标失败：\(error.localizedDescription)")
                    hint("获取图标失败：\(error.localizedDescription)", type: .critical)
                }
            }
        } else if FileManager.default.fileExists(atPath: input) {
            viewModel.setIcon(URL(fileURLWithPath: input))
            onClose()
        } else {
            hint("请输入 http(s) 开头的图片地址，或点「选择本地图片」。", type: .critical)
        }
    }
}
