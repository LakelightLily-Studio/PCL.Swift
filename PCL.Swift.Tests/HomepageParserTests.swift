//
//  HomepageParserTests.swift
//  PCL.Swift.Tests
//
//  原版主页 XAML → HomepageDocument 的解析回归测试。
//

import Testing
import Foundation
import Core

struct HomepageParserTests {
    @Test("解析卡片、富文本、提示条、按钮与图片")
    func parsesBasicNodes() throws {
        let xaml: String = """
        <local:MyCard Title="测试卡片" CanSwap="True" IsSwapped="True">
            <StackPanel>
                <TextBlock Text="第一行&#xA;第二行" FontSize="11" Foreground="#8C7721" />
                <local:MyHint Text="提示条" Theme="Yellow" />
                <local:MyButton Text="打开" ColorType="Highlight" EventType="打开网页" EventData="https://example.com" />
                <local:MyImage Source="https://example.com/a.png" Height="50" />
            </StackPanel>
        </local:MyCard>
        """
        let document: HomepageDocument = try HomepageXAMLParser.parse(xaml)
        #expect(document.nodes.count == 1)
        guard case .card(let title, let foldable, let folded, let children) = document.nodes[0] else {
            Issue.record("根节点不是卡片")
            return
        }
        #expect(title == "测试卡片")
        #expect(foldable)
        #expect(folded)
        guard case .stack(let axis, _, let nodes) = children[0] else {
            Issue.record("卡片内容不是 StackPanel")
            return
        }
        #expect(axis == .vertical)
        #expect(nodes.count == 4)
        #expect(nodes[0] == .richText(
            [.init(text: "第一行\n第二行", size: 11, color: "#8C7721")],
            alignment: .leading
        ))
        #expect(nodes[1] == .hint("提示条", .yellow))
        #expect(nodes[2] == .button("打开", .highlight, [.openURL(URL(string: "https://example.com")!)]))
        #expect(nodes[3] == .image(source: "https://example.com/a.png", height: 50, width: nil, alignment: .leading))
    }

    @Test("样式表与行内链接")
    func resolvesStylesAndInlineLinks() throws {
        let xaml: String = """
        <StackPanel>
            <StackPanel.Resources>
                <Style x:Key="H4" TargetType="Paragraph">
                    <Setter Property="FontSize" Value="16" />
                    <Setter Property="FontWeight" Value="Bold" />
                    <Setter Property="Foreground" Value="{DynamicResource ColorBrush4}" />
                </Style>
            </StackPanel.Resources>
            <Paragraph Style="{StaticResource H4}" Text="标题" />
            <ListItem><Paragraph><Underline><local:MyTextButton EventType="打开网页" EventData="https://example.com">链接</local:MyTextButton></Underline> 后面的文字</Paragraph></ListItem>
        </StackPanel>
        """
        let document: HomepageDocument = try HomepageXAMLParser.parse(xaml)
        guard case .stack(_, _, let nodes) = document.nodes[0] else {
            Issue.record("根节点不是 StackPanel")
            return
        }
        #expect(nodes.count == 2)

        guard case .richText(let titleRuns, _) = nodes[0] else {
            Issue.record("标题不是富文本")
            return
        }
        #expect(titleRuns.count == 1)
        #expect(titleRuns[0].text == "标题")
        #expect(titleRuns[0].size == 16)
        #expect(titleRuns[0].bold)
        #expect(titleRuns[0].color == "brush:4")

        guard case .richText(let listRuns, _) = nodes[1] else {
            Issue.record("列表项不是富文本")
            return
        }
        #expect(listRuns.count == 2)
        #expect(listRuns[0].text == "链接")
        #expect(listRuns[0].underline)
        #expect(listRuns[0].link == URL(string: "https://example.com"))
        #expect(listRuns[1].text.contains("后面的文字"))
    }

    @Test("未知容器展开，占位标记被清理")
    func flattensUnknownContainersAndCleansPlaceholders() throws {
        let xaml: String = """
        <StackPanel>
            <Border><TextBlock Text="{hint}" /></Border>
            <TextBlock Text="{variable:Name:默认值}" />
        </StackPanel>
        """
        let document: HomepageDocument = try HomepageXAMLParser.parse(xaml)
        // {hint} 与 {variable:...} 现在保留到渲染期再解析，解析阶段只丢弃其它花括号。
        #expect(document.nodes == [.stack(.vertical, .leading, [
            .richText([.init(text: "{hint}")], alignment: .leading),
            .richText([.init(text: "{variable:Name:默认值}")], alignment: .leading)
        ])])
    }

    @Test("多个根节点与 XML 声明都能解析")
    func acceptsMultipleRoots() throws {
        let xaml: String = """
        <?xml version="1.0" encoding="utf-8"?>
        <TextBlock Text="甲" />
        <TextBlock Text="乙" />
        """
        let document: HomepageDocument = try HomepageXAMLParser.parse(xaml)
        #expect(document.nodes.count == 2)
    }
}
