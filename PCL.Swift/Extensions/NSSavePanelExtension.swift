//
//  NSSavePanelExtension.swift
//  PCL.Swift
//
//  文件选择 / 保存面板一律以「附着在窗口上的模态 sheet」出现。
//
//  begin(completionHandler:) 会开一个独立的系统窗口，和启动器本体是两扇窗，
//  看起来像"点了之后弹出去一个窗口"；sheet 从标题栏下方滑出、挡住整个窗口，
//  与「模态」的语义一致，也和项目里自绘弹窗的观感更接近。
//
//  注意别把它命名成 beginSheet：NSWindow 自己就有 beginSheet(_:completionHandler:)，
//  同名会让编译器挑到 NSWindow 那个重载，报 "expected argument type NSWindow"。
//

import AppKit

extension NSSavePanel {
    /// 以 sheet 形式挂在当前窗口上（NSOpenPanel 也走这条）。
    ///
    /// 拿不到可见窗口时（极少见）退回 begin，至少不会点了没反应。
    func presentAsSheet(completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let window: NSWindow? = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first { $0.isVisible }
        guard let window else {
            begin(completionHandler: completion)
            return
        }
        window.beginSheet(self) { response in
            completion(response)
        }
    }
}
