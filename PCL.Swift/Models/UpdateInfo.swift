//
//  UpdateInfo.swift
//  PCL.Swift
//

import Foundation

/// 一次更新检查的结果。
///
/// 早期这里是 Cylorine Studio 的 update.json 的镜像结构；现在由 UpdateManager
/// 从国内清单（update.json）组装，失败时回退 GitHub Release。
struct UpdateInfo {
    struct Link {
        let name: String
        let url: URL
    }

    struct Downloads {
        /// 更新包地址：主地址在前，备用源（GitHub / 另一平台）在后。
        let urls: [URL]
        let size: Int
        /// 清单下发的 SHA-256；GitHub 渠道没有，所以是可选的。
        let sha256: String?
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
