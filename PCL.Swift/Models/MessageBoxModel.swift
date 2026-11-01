//
//  MessageBoxModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/20.
//

import SwiftUI
import AppKit

struct MessageBoxModel: Equatable, Identifiable {
    public let id: UUID = .init()
    public let title: String
    public let content: Content
    public let level: Level
    public let buttons: [Button]
    
    public enum Content {
        case text(text: String)
        case list(items: [ListItem])
        case input(initialContent: String?, placeholder: String?)
        /// 自定义实例图标：标题左侧一个实时预览，正文下面一行「输入框 + 选择本地图片」。
        ///
        /// preview 是打开时显示的图（当前图标）；输入框里填了图片地址或选了本地文件后，
        /// 视图自己会换成那张。
        case iconURL(initialContent: String?, placeholder: String?, preview: NSImage?)
    }
    
    public enum Level {
        case info, error
    }
    
    public static func == (lhs: MessageBoxModel, rhs: MessageBoxModel) -> Bool {
        return lhs.id == rhs.id
    }
    
    public struct Button {
        public let id: Int
        public let label: String
        public let type: MyButtonType
        public let onClick: (() -> Void)?
        
        /// 创建一个弹窗按钮。
        /// - Parameters:
        ///   - onClick: 点击回调，有值时被点击后不会关闭弹窗。
        public init(id: Int, label: String, type: MyButtonType, onClick: (() -> Void)? = nil) {
            self.id = id
            self.label = label
            self.type = type
            self.onClick = onClick
        }
        
        /// 创建一个 `id` 为 `1` 的“是”按钮。
        /// - Parameters:
        ///   - label: 按钮文本，默认为 `"确认"`。
        ///   - type: 按钮类型，默认为 `.normal`。
        public static func yes(label: String = "确认", type: MyButtonType = .normal) -> Button {
            return .init(id: 1, label: label, type: type)
        }
        
        /// 创建一个 `id` 为 `0` 的“否”按钮。
        /// - Parameters:
        ///   - label: 按钮文本，默认为 `"取消"`。
        ///   - type: 按钮类型，默认为 `.normal`。
        public static func no(label: String = "取消", type: MyButtonType = .normal) -> Button {
            return .init(id: 0, label: label, type: type)
        }
    }
}
