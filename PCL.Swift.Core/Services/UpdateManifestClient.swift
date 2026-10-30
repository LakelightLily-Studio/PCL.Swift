//
//  UpdateManifestClient.swift
//  PCL.Swift.Core
//
//  按顺序尝试国内清单入口，全部失败时抛出——由调用方回退到 GitHub Release。
//  成功时把清单与 ETag 落到 Caches/Update，断网时继续用上一份。
//

import Foundation

public struct UpdateManifestClient {
    public static let shared: UpdateManifestClient = .init()

    /// 清单入口。只有这几条是硬编码的，其余地址都由清单下发。
    public static let entryPoints: [URL] = [
        URL(string: "https://raw.gitcode.com/functy/pcl-swift-dist/raw/main/update.json")!,
        URL(string: "https://api.gitcode.com/api/v5/repos/functy/pcl-swift-dist/raw/update.json?ref=main")!,
        URL(string: "https://gitee.com/functy/pcl-swift-dist/raw/main/update.json")!,
    ]

    private var cacheDirectory: URL { URLConstants.cacheURL.appending(path: "Update") }
    private var cacheFile: URL { cacheDirectory.appending(path: "manifest.json") }
    private var etagFile: URL { cacheDirectory.appending(path: "manifest.etag") }

    public init() {}

    /// 拉取清单。逐个入口尝试，任一成功即返回；全失败时退回本地缓存（若有）。
    public func fetch() async throws -> UpdateManifest {
        var lastError: Error?
        for entry in Self.entryPoints {
            do {
                let data: Data = try await fetch(from: entry)
                let manifest: UpdateManifest = try JSONDecoder.shared.decode(UpdateManifest.self, from: data)
                try? save(data)
                return manifest
            } catch {
                lastError = error
                warn("清单入口失败 \(entry.host ?? "?")\(entry.path)：\(error.localizedDescription)")
            }
        }
        if let cached: UpdateManifest = loadCached() {
            warn("所有清单入口不可用，使用本地缓存")
            return cached
        }
        throw lastError ?? SimpleError("没有可用的更新清单入口。")
    }

    private func fetch(from url: URL) async throws -> Data {
        var headers: [String: String?] = ["Accept": "application/json"]
        if let etag = try? String(contentsOf: etagFile, encoding: .utf8), !etag.isEmpty {
            headers["If-None-Match"] = etag
        }
        let response = try await HTTPClient.shared.get(url, headers: headers, throwOnError: false, timeout: 8)
        if response.statusCode == 304, let cached = try? Data(contentsOf: cacheFile) {
            return cached
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SimpleError("清单返回 \(response.statusCode)")
        }
        if let etag = response.headers["etag"] {
            try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
        }
        return response.data
    }

    private func save(_ data: Data) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cacheFile, options: .atomic)
    }

    private func loadCached() -> UpdateManifest? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder.shared.decode(UpdateManifest.self, from: data)
    }
}
