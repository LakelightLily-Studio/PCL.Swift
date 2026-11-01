//
//  MessageBoxView.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/23.
//

import SwiftUI
import AppKit
import Core

struct MessageBoxView: View {
    private let model: MessageBoxModel
    @State private var selectedItemIndex: Int?
    @State private var inputText: String = ""
    /// 自定义图标弹窗里的实时预览。
    @State private var iconPreview: NSImage?
    
    init(model: MessageBoxModel) {
        self.model = model
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.cardBackground)
                .shadow(color: .color1.opacity(0.8), radius: 20)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    // 自定义图标弹窗：大标题左边放一个实时预览。
                    if case .iconURL = model.content {
                        iconPreviewView
                            .frame(width: 40, height: 40)
                    }
                    MyText(model.title, size: 23, color: foregroundColor)
                }
                .padding(.leading, 7)
                Rectangle()
                    .fill(foregroundColor)
                    .frame(height: 2)
                    .padding(.top, 9)
                    .padding(.bottom, 13)
                content
                    .frame(minHeight: 1)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 17)
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    ForEach(model.buttons, id: \.id) { button in
                        MyButton(button.label, textPadding: .init(top: 7, leading: 12, bottom: 7, trailing: 12), type: button.type) {
                            onButtonTap(button)
                        }
                        .fixedSize()
                    }
                }
            }
            .padding(22)
        }
        .frame(minWidth: 400, maxWidth: 800)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            switch model.content {
            case .input(let initialContent, _):
                if let initialContent {
                    inputText = initialContent
                }
            case .iconURL(let initialContent, _, let preview):
                inputText = initialContent ?? ""
                iconPreview = preview
            default:
                break
            }
        }
        // 只有自定义图标弹窗需要边输入边预览。
        .task(id: inputText) {
            guard case .iconURL = model.content else { return }
            await refreshIconPreview()
        }
    }
    
    private var foregroundColor: Color {
        switch model.level {
        case .info: .color2
        case .error: .red
        }
    }
    
    private var content: some View {
        Group {
            switch model.content {
            case .text(let text):
                MyText(text)
            case .list(let items):
                ScrollView {
                    MyList(items: items, onSelect: { self.selectedItemIndex = $0 })
                        .padding(.horizontal, 4)
                }
                .frame(maxHeight: 240)
            case .input(_, let placeholder):
                MyTextField(text: $inputText, placeholder: placeholder ?? "")
            case .iconURL(_, let placeholder, _):
                VStack(alignment: .leading, spacing: 10) {
                    MyText("从 URL 获取图标或使用本地图标")
                    HStack(spacing: 10) {
                        MyTextField(text: $inputText, placeholder: placeholder ?? "")
                        MyButton("选择本地图片") { chooseLocalImage() }
                            .fixedSize()
                    }
                }
                .frame(width: 420)
            }
        }
    }

    /// 弹窗里的图标预览：没图时是一块灰底占位。
    private var iconPreviewView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.colorGray7)
            if let iconPreview {
                Image(nsImage: iconPreview)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
            }
        }
    }

    /// 「选择本地图片」：把路径填进输入框，不直接关弹窗——用户还能改。
    private func chooseLocalImage() {
        let panel: NSOpenPanel = .init()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = "选择图标图片"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            inputText = url.path
        }
    }

    /// 输入框变了就刷新预览：URL 走网络（0.4s 防抖），本地路径直接读文件。
    private func refreshIconPreview() async {
        let input: String = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let url = URL(string: input), let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http") {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let response = try await HTTPClient.shared.get(url, timeout: 15)
                guard (200..<300).contains(response.statusCode), let image = NSImage(data: response.data) else { return }
                iconPreview = image
            } catch {
                // 预览失败不打扰用户，保存时再报错。
                debug("预览图标失败：\(error.localizedDescription)")
            }
        } else if FileManager.default.fileExists(atPath: input) {
            iconPreview = NSImage(contentsOfFile: input)
        }
    }
    
    private func onButtonTap(_ button: MessageBoxModel.Button) {
        switch model.content {
        case .text(_):
            MessageBoxManager.shared.onButtonTap(button)
        case .list(_):
            if button.id == MessageBoxManager.cancelButtonID { // 取消
                MessageBoxManager.shared.onListSelect(index: nil)
            } else if button.id == MessageBoxManager.okButtonID { // 确定
                MessageBoxManager.shared.onListSelect(index: selectedItemIndex)
            } else {
                MessageBoxManager.shared.onButtonTap(button)
            }
        case .input(_, _), .iconURL(_, _, _):
            if button.id == MessageBoxManager.cancelButtonID { // 取消
                MessageBoxManager.shared.onInputFinished(text: nil)
            } else if button.id == MessageBoxManager.okButtonID { // 保存 / 确定
                MessageBoxManager.shared.onInputFinished(text: inputText)
            } else {
                MessageBoxManager.shared.onButtonTap(button)
            }
        }
    }
}

#Preview {
    MessageBoxView(
        model: .init(
            title: "测试",
            content: .text(text: "test"),
            level: .info,
            buttons: [
                .init(id: 0, label: "高亮", type: .highlight),
                .init(id: 1, label: "普通", type: .normal),
                .init(id: 2, label: "千万别点", type: .red)
            ]
        )
    )
    .padding()
}
