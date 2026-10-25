//
//  PointingHandCursor.swift
//  PCL.Swift
//
//  悬停指针：可点击的东西在鼠标移上去时换成"小手"。
//
//  用 set/箭头 set 而不是 push/pop：push/pop 必须严格配对，弹窗、嵌套按钮、
//  视图在指针下被销毁都会漏掉一次 pop，指针就会一直停在手上。
//  set 是幂等的，最坏情况只是离开时被后一个 hover 覆盖，不会累积。
//

import SwiftUI
import AppKit

extension View {
    /// 悬停时把指针换成可点击的手形。
    /// - Parameter isEnabled: 置 false 时（例如按钮被禁用）保持箭头。
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content.onHover { inside in
            guard isEnabled else {
                if inside { NSCursor.arrow.set() }
                return
            }
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
