//
//  GitHubRelease+UpdateArchive.swift
//  PCL.Swift.Core
//

import Foundation

public extension GitHubRelease {
    /// 挑出可以直接替换 App Bundle 的更新包。
    ///
    /// 2.0.4 起发布的是**按架构分开**的包：PCL.Swift-<版本>-arm64.zip / -x86_64.zip。
    /// 2.0.3 及更早只有不带架构后缀的通用包，作为兜底；
    /// 只有另一种架构的包时返回 nil——装上去也跑不起来，不如不提示这次更新。
    /// - Parameter architecture: 当前运行的架构。
    func updateArchive(for architecture: Architecture) -> Asset? {
        let zips: [Asset] = assets.filter {
            $0.name.hasPrefix("PCL.Swift-") && $0.name.hasSuffix(".zip")
        }
        let token: String? = switch architecture {
        case .arm64: "arm64"
        case .x64: "x86_64"
        default: nil
        }
        if let token, let exact = zips.first(where: { $0.name.contains("-\(token)") }) {
            return exact
        }
        return zips.first { !$0.name.contains("-arm64") && !$0.name.contains("-x86_64") }
    }
}
