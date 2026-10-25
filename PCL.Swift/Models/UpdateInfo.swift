//
//  UpdateInfo.swift
//  PCL.Swift
//

import Foundation

/// 一次更新检查的结果。
///
/// 早期这里是 Cylorine Studio 的 update.json 的镜像结构；那份元数据不再跟随
/// 本仓库发版，所以现在由 UpdateManager 直接从 GitHub Release 组装。
struct UpdateInfo {
    struct Link {
        let name: String
        let url: URL
    }

    struct Downloads {
        /// 更新包地址（GitHub Release 资产里的 PCL.Swift-zip）。
        let url: URL
        let size: Int
        /// 旧渠道会带 SHA-1 校验值，GitHub Release 不提供，所以是可选的。
        let sha1: String?
    }

    /// 展示名，通常是 Release 标题（例如 2.0.1）。
    let name: String
    /// 参与比较的营销版本，例如 2.0.1。
    let version: String
    /// 弹窗里显示的一行摘要。
    let summary: String
    let updateLogLinks: [Link]
    let downloads: Downloads
}
