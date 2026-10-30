//
//  ResourceTranslation.swift
//  PCL.Swift
//
//  社区资源的译名表。
//
//  PCL2 的译名来自它自己的 CompName 数据库（mcmod 收录 + 人工校对），本启动器没有那份数据，
//  所以这里退一步：内置一份常用资源的中文名（Resources/Translations.json），
//  再允许用户在数据目录放一份同名文件覆盖/追加（Translations.json）。
//
//  查表顺序：slug（Modrinth 的 project id / CurseForge 的标题归一化）→ 标题归一化 → 原始标题。
//  查不到就返回 nil，调用方退回原名——**绝不**用机翻去猜，翻错比不翻更难认。
//

import Foundation
import Core

final class ResourceTranslation {
    static let shared: ResourceTranslation = .init()

    /// 归一化后的 key → 中文名。key 全是小写、空格换连字符。
    private let table: [String: String]

    private init() {
        var merged: [String: String] = Self.loadBundled()
        // 用户表覆盖内置表：改译名不用等发版。
        for (key, value) in Self.loadUserTable() {
            merged[Self.normalize(key)] = value
        }
        table = merged
    }

    /// 取译名。没有对应条目时返回 nil。
    /// - Parameters:
    ///   - slug: 站点上的项目标识（Modrinth 用 slug，CurseForge 传标题即可）。
    ///   - title: 项目标题。
    func name(slug: String?, title: String) -> String? {
        if let slug, let name = table[Self.normalize(slug)], !name.isEmpty {
            return name
        }
        if let name = table[Self.normalize(title)], !name.isEmpty {
            return name
        }
        return nil
    }

    /// 查表用的归一化：小写、去首尾空白、空格与下划线换成连字符。
    static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    /// 用户表的位置：数据目录下的 Translations.json。
    static var userTableURL: URL {
        URLConstants.applicationSupportURL.appending(path: "Translations.json")
    }

    private static func loadBundled() -> [String: String] {
        let url: URL = URLConstants.resourcesURL.appending(path: "Translations.json")
        return read(url, description: "内置译名表")
    }

    private static func loadUserTable() -> [String: String] {
        let url: URL = userTableURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return read(url, description: "用户译名表")
    }

    private static func read(_ url: URL, description: String) -> [String: String] {
        do {
            let data: Data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            // 译名只是锦上添花，读不到就当没有，不要让启动器起不来。
            warn("读取\(description)失败：\(error.localizedDescription)")
            return [:]
        }
    }
}
