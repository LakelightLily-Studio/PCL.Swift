//
//  ResourceFileNameTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 「文件名格式」。规则只有 Core 的 ResourceFileName 一处实现，
/// 这里把边界情况钉住：五种样式、没有译名、非法字符、Mod 的 ~ 处理。
struct ResourceFileNameTests {
    private func format(
        _ format: ResourceFileName.Format,
        name: String = "机械动力",
        originalName: String = "create-1.21.1-6.0.4.jar",
        type: ResourceType = .mod
    ) -> String {
        ResourceFileName.format(format: format, name: name, originalName: originalName, type: type)
    }

    @Test func rendersEveryStyle() {
        #expect(format(.bracketCN) == "【机械动力】create-1.21.1-6.0.4.jar")
        #expect(format(.bracketSquare) == "[机械动力] create-1.21.1-6.0.4.jar")
        #expect(format(.prefixDash) == "机械动力-create-1.21.1-6.0.4.jar")
        #expect(format(.suffixDash) == "create-1.21.1-6.0.4.jar-机械动力")
        #expect(format(.plain) == "create-1.21.1-6.0.4.jar")
    }

    @Test func keepsOriginalNameWithoutTranslation() {
        // 没有译名（项目名就是文件名主干）时，任何样式都退回原始文件名。
        for style in ResourceFileName.Format.allCases {
            #expect(format(style, name: "create-1.21.1-6.0.4") == "create-1.21.1-6.0.4.jar")
            #expect(format(style, name: "") == "create-1.21.1-6.0.4.jar")
        }
    }

    @Test func replacesIllegalCharacters() {
        #expect(format(.bracketSquare, name: "a/b:c") == "[a／b：c] create-1.21.1-6.0.4.jar")
        #expect(format(.bracketSquare, name: "a?b*c") == "[a？b＊c] create-1.21.1-6.0.4.jar")
        // 双引号直接删掉，带空格的冒号压成全角冒号。
        #expect(format(.bracketSquare, name: "a\"b: c") == "[ab：c] create-1.21.1-6.0.4.jar")
    }

    @Test func trimsAuthorSuffix() {
        // 形如「名称 (作者)」的标题只取括号前的部分。
        #expect(format(.bracketSquare, name: "机械动力 (simibubi)") == "[机械动力] create-1.21.1-6.0.4.jar")
        #expect(format(.bracketSquare, name: "机械动力 - simibubi") == "[机械动力] create-1.21.1-6.0.4.jar")
    }

    @Test func replacesTildeForModsOnly() {
        // ~ 会让 Mixin 加载失败，只有 Mod 需要换掉。
        #expect(format(.plain, originalName: "mod~1.0.jar") == "mod-1.0.jar")
        #expect(format(.plain, originalName: "pack~1.0.zip", type: .resourcepack) == "pack~1.0.zip")
    }

    @Test func fallsBackWhenOriginalNameIsEmpty() {
        #expect(format(.bracketSquare, name: "机械动力", originalName: "") == "机械动力")
    }
}
