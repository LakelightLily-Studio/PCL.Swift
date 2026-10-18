//
//  DSHInstanceListPage.swift
//  PCL.Swift
//
// DSH 目录页。与 Minecraft 的实例列表保持一致：点击某一项即选中该版本，
// 启动动作放在启动页的「启动游戏」按钮上，本页不提供启动入口。
//

import SwiftUI
import Core

/// DSH 当前选中的版本。整个 App 共用一个，供启动页读取。
@MainActor
final class DSHSelection: ObservableObject {
    public static let shared: DSHSelection = .init()

    @Published public private(set) var instance: DSHInstance? = DSHRuntime.detect()
    /// 当前「目录」是否是 DSH。启动页据此决定按钮是「启动游戏」还是「启动 DSH」。
    @Published public private(set) var isCurrentDirectory: Bool = DedicatedDefaults.isCurrentDirectory

    private init() {}

    public func select(_ instance: DSHInstance) {
        self.instance = instance
        isCurrentDirectory = true
        DedicatedDefaults.dshSelectedVersion = instance.id
        DedicatedDefaults.isCurrentDirectory = true
    }

    /// 切回 Minecraft 目录时调用。
    public func leave() {
        isCurrentDirectory = false
        DedicatedDefaults.isCurrentDirectory = false
    }

    /// 重新探测；已有选择且仍然可用时保留原选择。
    public func refresh() {
        let detected = DSHRuntime.detect()
        if let detected, detected.id == instance?.id {
            instance = detected
        } else {
            instance = detected
        }
    }
}

private enum DedicatedDefaults {
    private static let versionKey = "dshSelectedVersion"
    private static let directoryKey = "dshIsCurrentDirectory"

    static var dshSelectedVersion: String? {
        get { UserDefaults.standard.string(forKey: versionKey) }
        set { UserDefaults.standard.set(newValue, forKey: versionKey) }
    }

    /// 上次退出时是否停在 DSH 目录，用来恢复启动页的按钮形态。
    static var isCurrentDirectory: Bool {
        get { UserDefaults.standard.bool(forKey: directoryKey) }
        set { UserDefaults.standard.set(newValue, forKey: directoryKey) }
    }
}

struct DSHInstanceListPage: View {
    @ObservedObject private var selection: DSHSelection = .shared
    @State private var detected: DSHInstance? = DSHRuntime.detect()

    var body: some View {
        CardContainer {
            MyCard("当前目录：DSH", foldable: false) {
                infoLine(label: "安装形态") {
                    MyText(detected.map(formDescription) ?? "未检测到")
                }
                .padding(.top, 6)
                infoLine(label: "版本") { MyText(detected?.version ?? "-") }
                infoLine(label: "DSH 主目录") {
                    MyText(DSHRuntime.dshHome().path).textSelection(.enabled)
                }
                HStack(spacing: 15) {
                    MyButton("打开主目录") {
                        NSWorkspace.shared.open(DSHRuntime.dshHome())
                    }
                    .frame(width: 150)
                    MyButton("重新检测") {
                        selection.refresh()
                        detected = DSHRuntime.detect()
                        hint("已重新检测 DSH", type: .finish)
                    }
                    .frame(width: 150)
                    Spacer()
                }
                .frame(height: 35)
                .padding(.top, 6)
            }

            if let detected {
                MyCard("DSH 版本", folded: false) {
                    VStack(spacing: 0) {
                        MyListItem(.init(
                            image: .iconDSH,
                            name: detected.name,
                            description: selection.instance?.id == detected.id ? "\(detected.detail) · 已选择" : detected.detail
                        ))
                        .onTapGesture {
                            selection.select(detected)
                            hint("已选择 DSH \(detected.version)", type: .finish)
                            AppRouter.shared.removeLast()
                        }
                    }
                }
                .cardIndex(1)
            } else {
                MyCard("DSH 版本", folded: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        MyText("未检测到 DeepSeek Harness", color: .colorGray2)
                        MyText(
                            "需要先安装 DSH：把 DeepSeek Harness.app 放到「应用程序」，或者安装 dsh CLI 到 PATH 里。安装后点上方「重新检测」。",
                            size: 12,
                            color: .colorGray3
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
                .cardIndex(1)
            }
        }
        .onAppear {
            detected = DSHRuntime.detect()
        }
    }

    private func formDescription(_ instance: DSHInstance) -> String {
        switch instance.form {
        case .application: "桌面端 App"
        case .commandLine: "命令行 + Web UI"
        }
    }

    @ViewBuilder
    private func infoLine(label: String, @ViewBuilder body: () -> some View) -> some View {
        SettingRow(label, verticalPadding: 1, content: body)
    }
}
