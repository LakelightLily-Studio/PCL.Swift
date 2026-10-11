//
//  Side.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/22.
//

import Foundation

/// 客户端 / 服务端侧别，Modrinth 整合包索引与 Forge 安装器的 `sides` 字段共用同一套取值。
public enum Side: String, Codable {
    case client, server
}
