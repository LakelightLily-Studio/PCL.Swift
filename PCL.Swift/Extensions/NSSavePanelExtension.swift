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
//  **必须用 beginSheetModal(for:)，不能用 NSWindow.beginSheet(_:)**：
//  后者只是把面板挂上去，不会启动 NSSavePanel 自己的模态会话——面板能看见，
//  但点「取消 / 打开」全都没反应（按钮走的是 cancel:/ok:，没有会话可结束）。
//
//  方法也别叫 beginSheet：NSWindow 自带 beginSheet(_:completionHandler:)，
//  同名会让编译器挑到那个重载，报 "expected argument type NSWindow"。
//

import AppKit

extension NSSavePanel {
    /// 以 sheet 形式挂在当前窗口上（NSOpenPanel 也走这条）。
    ///
    /// 拿不到可见窗口时（极少见）退回 begin，至少不会点了没反应。
    func presentAsSheet(completion: @escaping (NSApplication.ModalResponse) -> Void) {
        // 不要用 keyWindow：下拉框的 SelectPanel 是 NSPanel，可能会短暂成为 key，
        // 把 sheet 挂到一个马上要关掉的面板上，看起来就是"弹出来但点不动"。
        let candidates: [NSWindow] = NSApplication.shared.windows.filter { window in
            window.isVisible && !(window is NSPanel)
        }
        let window: NSWindow? = candidates.first { $0.isKeyWindow }
            ?? candidates.first { $0 is AppWindow }
            ?? candidates.first
        guard let window else {
            begin(completionHandler: completion)
            return
        }
        beginSheetModal(for: window) { response in
            completion(response)
        }
    }
}
