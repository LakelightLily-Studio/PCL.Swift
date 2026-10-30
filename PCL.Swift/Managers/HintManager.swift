//
//  HintManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/13.
//

import Foundation

class HintManager: ObservableObject {
    public static let shared: HintManager = .init()
    @Published public var hints: [HintModel] = []
    
    /// 弹出提示。
    /// - Parameters:
    ///   - text: 提示内容。
    ///   - type: 提示类型，默认为 `info`（蓝色）。
    ///   - time: 提示显示时长。
    public func hint(_ text: String, type: HintModel.`Type` = .info, time: Double = 2.0) {
        let hint: HintModel = .init(text: text, type: type)
        hints.append(hint)
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            self.dismiss(hint.id)
        }
    }
    
    /// 播完退场动画再移除（PCL2 的 MyHint.AniDispose：缩放 + 淡出 + 高度收 0）。
    private func dismiss(_ id: UUID) {
        guard let index = hints.firstIndex(where: { $0.id == id }), !hints[index].isDismissing else { return }
        hints[index].isDismissing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + HintExit.window) {
            self.hints.removeAll(where: { $0.id == id })
        }
    }
    
    private init() {}
}

/// 弹出提示。
/// - Parameters:
///   - text: 提示内容。
///   - type: 提示类型，默认为 `info`（蓝色）。
///   - time: 提示显示时长。
func hint(_ text: String, type: HintModel.`Type` = .info, time: Double = 2.0) {
    DispatchQueue.main.async {
        HintManager.shared.hint(text, type: type, time: time)
    }
}
