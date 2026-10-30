//
//  UpdateManifest.swift
//  PCL.Swift.Core
//
//  国内分发清单（update.json）的 DTO。
//
//  清单是客户端唯一硬编码的入口，里面下发更新包、公告与图片的绝对地址：
//  换源、换 CDN 只改这一份 JSON，不用发版。字段全部 decodeIfPresent + 默认值，
//  旧清单缺字段时不能整体解码失败——那会让所有用户同时收不到更新。
//

import Foundation

public struct UpdateManifest: Decodable {
    public struct Asset: Decodable {
        public let url: URL
        /// 备用地址（GitCode 直链 / GitHub Release）。客户端按顺序尝试。
        public let mirrors: [URL]
        public let size: Int?
        public let sha256: String?

        private enum CodingKeys: String, CodingKey {
            case url, mirrors, size, sha256
        }

        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.url = try container.decode(URL.self, forKey: .url)
            self.mirrors = (try? container.decodeIfPresent([URL].self, forKey: .mirrors)) .flatMap { $0 } ?? []
            self.size = try? container.decodeIfPresent(Int.self, forKey: .size)
            self.sha256 = try? container.decodeIfPresent(String.self, forKey: .sha256)
        }

        /// 主地址 + 备用地址，已去重。
        public var allURLs: [URL] {
            var result: [URL] = [url]
            for mirror in mirrors where !result.contains(mirror) {
                result.append(mirror)
            }
            return result
        }
    }

    public struct Release: Decodable {
        public let version: String
        public let tag: String?
        public let name: String?
        public let summary: String?
        public let notesURL: URL?
        public let prerelease: Bool
        /// 撤包：跳过该版本继续找更旧的可用版本。
        public let yanked: Bool
        /// 灰度百分比，0…100。
        public let rollout: Int
        public let assets: [String: Asset]

        private enum CodingKeys: String, CodingKey {
            case version, tag, name, summary
            case notesURL = "notes_url"
            case prerelease, yanked, rollout, assets
        }

        public init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try container.decode(String.self, forKey: .version)
            self.tag = try? container.decodeIfPresent(String.self, forKey: .tag)
            self.name = try? container.decodeIfPresent(String.self, forKey: .name)
            self.summary = try? container.decodeIfPresent(String.self, forKey: .summary)
            self.notesURL = try? container.decodeIfPresent(URL.self, forKey: .notesURL)
            self.prerelease = (try? container.decodeIfPresent(Bool.self, forKey: .prerelease)) ?? false
            self.yanked = (try? container.decodeIfPresent(Bool.self, forKey: .yanked)) ?? false
            self.rollout = (try? container.decodeIfPresent(Int.self, forKey: .rollout)) ?? 100
            self.assets = (try? container.decodeIfPresent([String: Asset].self, forKey: .assets)) ?? [:]
        }

        /// 按运行架构挑包。清单用 "arm64" / "x86_64" 两个键，
        /// 与 Architecture 的 rawValue（x64）不同名，映射只在这里做一次。
        public func asset(for architecture: Architecture) -> Asset? {
            switch architecture {
            case .arm64:
                return assets["arm64"] ?? assets["universal"]
            case .x64:
                return assets["x86_64"] ?? assets["universal"]
            case .fatFile:
                return assets["universal"] ?? assets["arm64"] ?? assets["x86_64"]
            case .unknown:
                return nil
            }
        }
    }

    public let schema: Int
    public let channel: String
    public let latest: String?
    public let releases: [Release]

    private enum CodingKeys: String, CodingKey {
        case schema, channel, latest, releases
    }

    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.schema = (try? container.decodeIfPresent(Int.self, forKey: .schema)) ?? 1
        self.channel = (try? container.decodeIfPresent(String.self, forKey: .channel)) ?? "stable"
        self.latest = try? container.decodeIfPresent(String.self, forKey: .latest)
        self.releases = (try? container.decodeIfPresent([Release].self, forKey: .releases)) ?? []
    }
}
