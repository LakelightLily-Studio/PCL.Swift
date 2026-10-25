//
//  ResourceFileNameTests.swift
//  PCL.Swift.Tests
//

import Foundation
import Core
import Testing

/// 「文件名格式」的模板渲染。规则只有 Core 的 ResourceFileName 一处实现，
/// 这里把边界情况钉住：占位符缺值、扩展名重复、非法字符、空模板。
struct ResourceFileNameTests {
    private func format(
        _ template: String,
        name: String = "Sodium",
        version: String? = "0.6.13",
        loader: ModLoader? = .fabric,
        type: ResourceType = .mod,
        fileExtension: String = "jar",
        fallback: String = "sodium-0.6.13.jar"
    ) -> String {
        ResourceFileName.format(
            template: template,
            name: name,
            version: version,
            loader: loader,
            type: type,
            fileExtension: fileExtension,
            fallback: fallback
        )
    }

    @Test func rendersDefaultTemplate() {
        #expect(format("{name}-{version}") == "Sodium-0.6.13.jar")
    }

    @Test func replacesAllPlaceholders() {
        #expect(format("{name}-{version}-{loader}", loader: .fabric) == "Sodium-0.6.13-fabric.jar")
        #expect(format("{type}/{name}", type: .shader) == "shader-Sodium.jar")
    }

    @Test func collapsesSeparatorsWhenValuesAreMissing() {
        // 版本号缺失时会留下 "Sodium--" 这类残骸，必须折叠并裁掉尾部分隔符。
        #expect(format("{name}-{version}", version: nil) == "Sodium.jar")
        #expect(format("[{loader}] {name}", loader: nil) == "Sodium.jar")
    }

    @Test func keepsOriginalExtensionWithoutDuplicating() {
        #expect(format("{name}.jar") == "Sodium.jar")
        #expect(format("{name}.JAR") == "Sodium.JAR")
    }

    @Test func fallsBackWhenTemplateRendersNothing() {
        #expect(format("") == "sodium-0.6.13.jar")
        #expect(format("---") == "sodium-0.6.13.jar")
        #expect(format("{version}", version: nil) == "sodium-0.6.13.jar")
    }

    @Test func stripsPathSeparators() {
        #expect(format("{name}", name: "a/b:c") == "a-b-c.jar")
    }
}
