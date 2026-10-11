//
//  MinecraftVersion.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/11/24.
//

import Foundation

public class MinecraftVersion: Codable, Comparable, Equatable, Hashable, CustomStringConvertible {
    public let id: String
    
    public init(_ id: String) {
        self.id = id
    }
    
    public required init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.id = try container.decode(String.self)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.id)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: MinecraftVersion, rhs: MinecraftVersion) -> Bool {
        return lhs.id == rhs.id
    }
    
    public static func < (lhs: MinecraftVersion, rhs: MinecraftVersion) -> Bool {
        return isOrdered(lhs, before: rhs, using: VersionManifest.shared)
    }
    
    /// 版本先后判定的全部规则，清单作为显式参数传入。
    ///
    /// 两个版本都能在清单里查到发布时间时按时间排序；否则退化为按版本号做自然序
    /// 字符串比较（"1.21.11-pre2" > "1.21.10"）。
    ///
    /// 之所以把规则单独提出来：`<` 依赖 `VersionManifest.shared` 的加载状态，
    /// 而清单由启动阶段缓存同步与网络异步两条路径写入。规则本身与全局状态无关，
    /// 拆出来之后可以脱离启动流程直接测试。
    public static func isOrdered(_ lhs: MinecraftVersion, before rhs: MinecraftVersion, using manifest: VersionManifest?) -> Bool {
        if let lVersion = manifest?.version(for: lhs.id), let rVersion = manifest?.version(for: rhs.id) {
            return lVersion.releaseTime < rVersion.releaseTime
        }
        return lhs.id.compare(rhs.id, options: .numeric) == .orderedAscending
    }
    
    public lazy var description: String = { id }()
    
    public enum VersionType: Decodable {
        case release, snapshot, old, aprilFool
        
        init?(stringValue: String) {
            switch stringValue {
            case "release": self = .release
            case "snapshot": self = .snapshot
            case "old_beta", "old_alpha": self = .old
            default: return nil
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let stringValue: String = try container.decode(String.self)
            guard let result = VersionType(stringValue: stringValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "无法解析 VersionType: \(stringValue)"
                )
            }
            self = result
        }
    }
}
