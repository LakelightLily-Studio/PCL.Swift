//
//  ResourceRefreshCenter.swift
//  PCL.Swift
//
//  社区资源页的「刷新」信号。
//
//  侧边栏条目上的刷新按钮和资源页不在同一棵视图树里（一个在 AppSidebarView，
//  一个在 AppRouterView），没法直接调用页面的搜索方法。这里用一个按类型计数的
//  令牌把它们连起来：侧边栏点刷新 → 对应类型的计数 +1 → 该类型的页面收到后
//  用当前筛选条件重新搜索一次（与原版 PageDownloadLeft 的 Refresh 一致）。
//

import Foundation
import Core

@MainActor
final class ResourceRefreshCenter: ObservableObject {
    static let shared: ResourceRefreshCenter = .init()

    /// 每种资源类型的刷新计数。
    @Published private(set) var tokens: [ResourceType: Int] = [:]

    private init() {}

    /// 请求刷新某一类型的资源页。
    func request(_ type: ResourceType) {
        tokens[type, default: 0] += 1
    }

    /// 当前计数，页面用它做 `onChange` 的观察值。
    func token(for type: ResourceType) -> Int {
        tokens[type] ?? 0
    }
}
