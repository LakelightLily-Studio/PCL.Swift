//
//  GameWindowTitle.swift
//  PCL.Swift.Core
//
//  把用户设置的窗口标题写到 Minecraft 的窗口上。
//
//  Minecraft 本身没有"改窗口标题"的启动参数，Windows 上 PCL 是用
//  SetWindowText 改的；macOS 对应的能力是 Accessibility API（AXUIElement）。
//  这需要用户在「系统设置 → 隐私与安全性 → 辅助功能」里授权，未授权时
//  只能静默降级——绝不能因为改不了标题就让游戏起不来。
//

import Foundation
import ApplicationServices

public enum GameWindowTitle {
    /// 本进程是否已被授予辅助功能权限。
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 申请辅助功能权限（弹出系统引导）。
    ///
    /// 返回的是"当前是否已授权"，而不是"是否弹了框"：
    /// 系统弹框是异步的，调用方拿到 false 时应提示用户手动去开。
    @discardableResult
    public static func requestPermission() -> Bool {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 把指定进程的所有窗口标题改成 title。
    ///
    /// - Parameters:
    ///   - title: 目标标题。空串直接返回。
    ///   - pid: 游戏进程的 PID。
    /// - Returns: 成功改写的窗口数量。
    @discardableResult
    public static func apply(title: String, to processIdentifier: Int32) -> Int {
        let trimmed: String = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard AXIsProcessTrusted() else {
            warn("未获得辅助功能权限，无法修改游戏窗口标题")
            return 0
        }

        let application: AXUIElement = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        let result: AXError = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            warn("读取游戏窗口列表失败（AXError " + String(result.rawValue) + "）")
            return 0
        }

        var renamed: Int = 0
        for window in windows {
            let setResult: AXError = AXUIElementSetAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                trimmed as CFTypeRef
            )
            if setResult == .success {
                renamed += 1
            } else {
                debug("设置窗口标题失败（AXError " + String(setResult.rawValue) + "）")
            }
        }
        if renamed > 0 {
            log("已将 " + String(renamed) + " 个游戏窗口标题改为「" + trimmed + "」")
        }
        return renamed
    }
}
