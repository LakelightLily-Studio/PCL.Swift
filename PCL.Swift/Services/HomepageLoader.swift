//
//  HomepageLoader.swift
//  PCL.Swift
//
//  自定义主页的取内容逻辑：本地固定文件，或联网下载。
//
//  本地文件路径与 PCL2 一样固定（数据目录下的 Custom.xaml），
//  设置里只提供「打开文件夹 / 刷新」，不做文件选择器——原作者的主页教程也是这么用的。
//

import Foundation
import Core

enum HomepageLoader {
    /// 「Minecraft 新闻」预设的地址。原版预设就是下载这份 XAML 再解析。
    static let minecraftNewsPresetURL: URL = URL(string: "https://mcnews.meloong.com")!

    /// 下载主页时使用的 User-Agent。
    ///
    /// 这些第三方主页服务器按 UA 白名单放行 PCL：实测同一地址用浏览器 UA 会 403、
    /// 用裸 "PCL" 会 514，只有 "PCL2/x.y.z" 才返回内容。格式与 PCL2 的
    /// `PCL2/{版本}.{构建类型}` 一致，后缀里带上本启动器自己的版本便于对方统计。
    private static var userAgent: String {
        "PCL2/2.9.4 (PCL.Swift/\(Metadata.appVersion))"
    }

    /// 本地主页文件：`~/Library/Application Support/PCL.Swift/Custom.xaml`。
    static var localFileURL: URL {
        URLConstants.applicationSupportURL.appending(path: "Custom.xaml")
    }

    static func loadLocalFile() throws -> HomepageDocument {
        guard FileManager.default.fileExists(atPath: localFileURL.path) else {
            throw HomepageLoadError.missingLocalFile(localFileURL)
        }
        let content: String
        do {
            content = try String(contentsOf: localFileURL, encoding: .utf8)
        } catch {
            throw HomepageLoadError.unreadableLocalFile(error)
        }
        return try HomepageXAMLParser.parse(content)
    }

    static func loadRemote(_ url: URL) async throws -> HomepageDocument {
        let data: Data
        do {
            data = try await HTTPClient.shared.get(
                url,
                headers: ["User-Agent": userAgent, "Accept": "*/*"],
                revalidate: true,
                timeout: 20
            ).data
        } catch {
            throw HomepageLoadError.downloadFailed(error)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw HomepageLoadError.invalidEncoding
        }
        return try HomepageXAMLParser.parse(content)
    }
}

enum HomepageLoadError: LocalizedError {
    case missingLocalFile(URL)
    case unreadableLocalFile(Error)
    case downloadFailed(Error)
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .missingLocalFile(let url):
            "找不到主页文件：" + url.path
        case .unreadableLocalFile(let error):
            "读取主页文件失败：" + error.localizedDescription
        case .downloadFailed(let error):
            "下载主页失败：" + error.localizedDescription
        case .invalidEncoding:
            "主页内容不是 UTF-8 文本"
        }
    }
}
