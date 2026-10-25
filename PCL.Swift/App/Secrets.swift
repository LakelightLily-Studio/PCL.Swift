//
//  Secrets.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation
import Core

struct Secrets {
    public static let shared: Secrets = .init()

    /// 打包进 App 的 CurseForge API Key。
    ///
    /// 来源优先级：环境变量 PCLMAC_CURSE_FORGE_API_KEY → Secrets.local.properties
    /// → Secrets.properties。前两者供本地开发，最后一个是 CI 在构建时用仓库 secret
    /// 重写的（仓库里的那份只是模板，不含真实 Key）。
    private let bundledCurseforgeApiKey: String?

    /// 当前生效的 CurseForge API Key。
    ///
    /// 只有内置这一层：Key 由构建时注入，用户不再需要（也不允许）手填。
    /// 空白串一律按「没有」处理，免得拿空 Key 去请求——那样只会得到 401。
    public var curseforgeApiKey: String? {
        bundledCurseforgeApiKey
    }

    /// 按当前 Key 构造客户端。没有可用 Key 时返回 nil，让调用方走「缺少 Key」的分支，
    /// 而不是拿空 Key 去请求——那样只会得到 401，错误信息还看不出原因（Issue #4）。
    public var curseforgeClient: CurseForgeAPIClient? {
        curseforgeApiKey.map { .init(apiKey: $0) }
    }

    private init() {
        var values: [String: String] = Self.load("Secrets.properties")
        // 本地开发用的覆盖文件，条目会盖掉打包文件里的同名键。
        // 它在 .gitignore 里：真实 Key 不进仓库，CI 走 Secrets.properties 那条路。
        for (key, value) in Self.load("Secrets.local.properties") {
            values[key] = value
        }

        let bundled: String? = CurseforgeAPIKeyResolver.resolve(
            userProvided: ProcessInfo.processInfo.environment["PCLMAC_CURSE_FORGE_API_KEY"],
            bundled: values["CURSE_FORGE_API_KEY"]
        )
        bundledCurseforgeApiKey = bundled
        if bundled != nil {
            // 只记"有没有"，不记内容：日志是用户会随手贴出来的东西。
            log("已加载 CurseForge API Key")
        } else {
            warn("没有可用的 CurseForge API Key：CurseForge 格式的整合包无法导入，请更新到内置了 Key 的版本。")
        }
    }

    private static func load(_ name: String) -> [String: String] {
        let url: URL = URLConstants.resourcesURL.appending(path: name)
        // 文件不存在是正常情况：仓库只带模板，本地覆盖文件按需创建，CI 只在构建时生成。
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            return try PropertiesLoader.load(at: url)
        } catch {
            err("加载 \(name) 失败：\(error.localizedDescription)")
            return [:]
        }
    }
}
