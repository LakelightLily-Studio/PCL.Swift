//
//  LauncherConfigObserver.swift
//  PCL.Swift
//
//  LauncherConfig 是普通 class，不是 ObservableObject：它的字段被大量
//  非 UI 代码直接读写，改成 ObservableObject 会让每处赋值都触发一次视图刷新。
//
//  但个性化设置页确实需要"改完立刻重画"。折中方案是这个极薄的观察者：
//  设置页在写入后调 touch()，由它发一次 objectWillChange。
//

import Foundation
import Combine

@MainActor
final class LauncherConfigObserver: ObservableObject {
    static let shared: LauncherConfigObserver = .init()

    /// 单调递增的变更计数。
    ///
    /// 视图用 .onChange(of: tick) 订阅：objectWillChange 只对 @ObservedObject
    /// 的持有者生效，拿不到同一个实例的深视图靠这个计数值做 key 最省事。
    @Published private(set) var tick: Int = 0

    private init() {}

    /// 通知所有观察者：LauncherConfig 的内容变了。
    func touch() {
        tick += 1
        objectWillChange.send()
    }
}
