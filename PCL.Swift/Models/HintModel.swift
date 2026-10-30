//
//  HintModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/13.
//

import Foundation

struct HintModel: Identifiable, Equatable {
    public let text: String
    public let type: `Type`
    public let id: UUID = .init()
    /// 是否正在退场。
    ///
    /// 提示条不能直接从数组里删：删掉等于瞬间消失，没有退场动画可播。
    /// 所以先把它标成退场、让视图播完动画，再由 HintManager 真正移除。
    public var isDismissing: Bool = false
    
    public enum `Type` {
        case info, finish, critical
    }
}
