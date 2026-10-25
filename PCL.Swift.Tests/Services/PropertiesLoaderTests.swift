//
//  PropertiesLoaderTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 这些用例守着 Issue #4 的那条回归：CI 在 secret 缺失时曾写出
/// "CURSE_FORGE_API_KEY="（空值），旧实现把这种行判成 invalidLine，
/// 于是整份 Secrets.properties 解析失败，连同一文件里其它正常的键一起丢掉。
struct PropertiesLoaderTests {
    @Test func parsesNormalEntries() throws {
        let values: [String: String] = try PropertiesLoader.load(from: "A=1\nB=2")
        #expect(values["A"] == "1")
        #expect(values["B"] == "2")
    }

    @Test func keepsEmptyValueInsteadOfFailing() throws {
        let values: [String: String] = try PropertiesLoader.load(
            from: "CURSE_FORGE_API_KEY=\nOTHER_KEY=value"
        )
        #expect(values["CURSE_FORGE_API_KEY"] == "")
        // 关键点：空值行不能让同一文件里的其它键一起消失。
        #expect(values["OTHER_KEY"] == "value")
    }

    @Test func ignoresCommentsAndBlankLines() throws {
        let values: [String: String] = try PropertiesLoader.load(
            from: """
            # comment
              # indented comment

            KEY=value
            """
        )
        #expect(values == ["KEY": "value"])
    }

    @Test func trimsWhitespaceAndQuotes() throws {
        let values: [String: String] = try PropertiesLoader.load(from: "  KEY  =  \"value\"  ")
        #expect(values["KEY"] == "value")
    }

    @Test func supportsCarriageReturnLineEndings() throws {
        // Swift 把 \r\n 当作一个 Character，按 "\n" 切是切不开的：
        // 一份 CRLF 的 Secrets.properties 会整份变成一行，同样表现为"所有 Key 都丢了"。
        let values: [String: String] = try PropertiesLoader.load(from: "A=1\r\nB=2\r\n")
        #expect(values["A"] == "1")
        #expect(values["B"] == "2")
    }

    @Test func supportsCarriageReturnOnlyLineEndings() throws {
        let values: [String: String] = try PropertiesLoader.load(from: "A=1\rB=2\r")
        #expect(values["A"] == "1")
        #expect(values["B"] == "2")
    }

    @Test func rejectsDuplicateKeys() {
        #expect(throws: PropertiesLoader.LoadError.self) {
            try PropertiesLoader.load(from: "A=1\nA=2")
        }
    }

    @Test func rejectsLinesWithoutSeparator() {
        #expect(throws: PropertiesLoader.LoadError.self) {
            try PropertiesLoader.load(from: "JUST_A_KEY")
        }
    }

    @Test func rejectsEntriesWithoutKey() {
        #expect(throws: PropertiesLoader.LoadError.self) {
            try PropertiesLoader.load(from: "=value")
        }
    }
}
