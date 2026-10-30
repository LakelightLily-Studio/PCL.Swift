//
//  ProjectVersionModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/19.
//

import Foundation
import Core

/// 要下载的那个文件。
///
/// Modrinth 与 CurseForge 的文件模型字段不一样，但安装流程只用到
/// 「文件名 / 下载地址 / SHA-1」这三样，所以在这里统一成一个结构。
struct ProjectFile {
    let name: String
    let url: URL
    let sha1: String?
}

struct ProjectVersionModel: Identifiable {
    struct Dependency: Identifiable {
        public let id: UUID = .init()
        public let versionId: String?
        public let projectId: String
        public let project: ProjectListItemModel
    }
    
    public let id: String
    public let name: String
    public let version: String
    public let downloads: String
    public let datePublished: String
    public let requiredDependencies: [Dependency]
    public let type: ModrinthVersion.VersionType
    public let primaryFile: ProjectFile?
    public let gameVersion: String
    public let loader: ModLoader?
}
