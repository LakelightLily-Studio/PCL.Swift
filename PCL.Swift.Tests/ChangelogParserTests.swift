//
//  ChangelogParserTests.swift
//  PCL.Swift.Tests
//
//  主页预设「PCL.Swift 更新日志」的解析回归测试。
//
//  这份格式是我们自己定的，但两处最容易写错的地方都在"拼接"上：
//  跨行条目要拼回一句（中文之间不能补空格），行内标记要拆成 runs。
//

import Testing
import Foundation
import Core

struct ChangelogParserTests {
    @Test("解析版本、小节与条目")
    func parsesEntries() {
        let markdown: String = """
        # 更新日志

        ## 2.0.5

        ### 新增

        - **国内更新源**：优先读国内清单。
        - 第二项。

        ### 修复

        - 修掉一个问题。

        ## 2.0.4

        ### 改进

        - 旧版本的一行。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        #expect(document.entries.count == 2)
        #expect(document.entries[0].version == "2.0.5")
        #expect(document.entries[0].sections.count == 2)
        #expect(document.entries[0].sections[0].title == "新增")
        #expect(document.entries[0].sections[0].items.count == 2)
        #expect(document.entries[0].sections[0].items[0].text == "国内更新源：优先读国内清单。")
        #expect(document.entries[0].sections[0].items[0].runs[0].bold)
        #expect(!document.entries[0].sections[0].items[0].runs[1].bold)
        #expect(document.entries[0].sections[1].title == "修复")
        #expect(document.entries[1].version == "2.0.4")
        #expect(document.entries[1].sections[0].items[0].text == "旧版本的一行。")
    }

    @Test("跨行的中文条目拼回一句且不补空格")
    func joinsSoftWrappedChineseLines() {
        let markdown: String = """
        ## 2.0.5

        ### 新增

        - **国内更新源**：清单下发更新包地址、
          SHA-256 与备用镜像，以后换源不用发版。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        let item: ChangelogItem = document.entries[0].sections[0].items[0]
        #expect(item.text == "国内更新源：清单下发更新包地址、SHA-256 与备用镜像，以后换源不用发版。")
        #expect(item.text.contains("地址、SHA-256"))
    }

    @Test("中文与行内代码交界处补一个空格")
    func joinsCJKAndCodeSpan() {
        let markdown: String = """
        ## 2.0.5

        - 指定图打不开时自动解绑并退回
          `Pictures/` 里的随机图。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        let item: ChangelogItem = document.entries[0].sections[0].items[0]
        #expect(item.text == "指定图打不开时自动解绑并退回 Pictures/ 里的随机图。")
    }

    @Test("跨行的西文条目补空格")
    func joinsSoftWrappedLatinLines() {
        let markdown: String = """
        ## 2.0.5

        - the launcher now reads
          the manifest first
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        #expect(document.entries[0].sections[0].items[0].text == "the launcher now reads the manifest first")
    }

    @Test("反引号拆成代码 run")
    func parsesInlineCode() {
        let markdown: String = """
        ## 2.0.5

        - 译名表放在 `Translations.json` 里，可以覆盖。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        let item: ChangelogItem = document.entries[0].sections[0].items[0]
        #expect(item.runs.count == 3)
        #expect(item.runs[1].text == "Translations.json")
        #expect(item.runs[1].code)
        #expect(item.text == "译名表放在 Translations.json 里，可以覆盖。")
    }

    @Test("没有小节标题的条目归入空标题小节")
    func itemsWithoutSectionHeading() {
        let markdown: String = """
        ## 2.0.5

        - 直接一条。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        #expect(document.entries.count == 1)
        #expect(document.entries[0].sections.count == 1)
        #expect(document.entries[0].sections[0].title.isEmpty)
        #expect(document.entries[0].sections[0].items.count == 1)
    }

    @Test("只有标题、没有条目的版本与小节不产出")
    func dropsEmptySectionsAndEntries() {
        let markdown: String = """
        # 更新日志

        ## 2.0.5

        ### 新增

        ### 修复

        - 只有这一条。

        ## 2.0.4

        ### 改进
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        #expect(document.entries.count == 1)
        #expect(document.entries[0].version == "2.0.5")
        #expect(document.entries[0].sections.count == 1)
        #expect(document.entries[0].sections[0].title == "修复")
    }

    @Test("空行结算上一条，导语被忽略")
    func blankLinesSeparateItems() {
        let markdown: String = """
        # 更新日志

        这里是导语，不该出现在任何条目里。

        ## 2.0.5

        - 第一条。

        - 第二条。
        """
        let document: ChangelogDocument = ChangelogParser.parse(markdown)
        let items: [ChangelogItem] = document.entries[0].sections[0].items
        #expect(items.count == 2)
        #expect(items[0].text == "第一条。")
        #expect(items[1].text == "第二条。")
    }

    @Test("空文档解析为空列表")
    func emptyMarkdown() {
        #expect(ChangelogParser.parse("").entries.isEmpty)
        #expect(ChangelogParser.parse("# 更新日志\n\n").entries.isEmpty)
    }
}
