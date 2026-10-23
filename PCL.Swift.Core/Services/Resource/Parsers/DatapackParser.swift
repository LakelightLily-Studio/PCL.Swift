//
//  DatapackParser.swift
//  PCL.Swift.Core
//
//  数据包（datapack）的元数据解析。
//
//  数据包与资源包同构：都是一个 zip，根目录有 pack.mcmeta。
//  区别在加载位置——数据包放进存档的 datapacks/，资源包放进实例的 resourcepacks/。
//  所以两者解析逻辑几乎相同，但不能复用同一个 parser：ResourceLoadService
//  按 parser 的 type 决定"这个文件是什么"，共用一个 parser 会让数据包被认成资源包。
//

import Foundation
import ZIPFoundation
import SwiftyJSON

enum DatapackParser: ResourceParser {
    static let type: ResourceType = .datapack

    static func canHandle(fileURL: URL, archive: Archive) -> Bool {
        // 数据包与资源包都靠 pack.mcmeta 识别，靠 pack_format 的取值区分：
        // 资源包的 pack_format 从 1 开始连续编号，数据包有自己的一套编号，
        // 但两者取值范围重叠，无法可靠区分。所以这里只认"名字里带 datapack"
        // 或目录层级里有 datapacks/ 的情况，其余交给资源包 parser。
        let name: String = fileURL.lastPathComponent.lowercased()
        if name.contains("datapack") || name.contains("data_pack") { return true }
        return fileURL.deletingLastPathComponent().lastPathComponent == "datapacks"
    }

    static func parse(fileURL: URL, archive: Archive, remoteInfo: ResourceRemoteLookupService.RemoteResourceInfo?) -> ResourceParseResult? {
        guard let entry = archive["pack.mcmeta"] else { return nil }

        var description: String? = remoteInfo?.description
        if let data = try? archive.extract(entry),
           let json = try? JSON(data: data),
           let packDescription = json["pack"]["description"].string {
            description = description ?? packDescription
        }

        return .init(
            name: remoteInfo?.name ?? fileURL.deletingPathExtension().lastPathComponent,
            version: remoteInfo?.version,
            description: description,
            iconPath: "pack.png",
            loaders: []
        )
    }
}
