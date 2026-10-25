//
//  HomepageDocument.swift
//  PCL.Swift.Core
//
//  主页自定义内容的中间表示（解析在 HomepageXAMLParser，渲染在 App 层）。
//

import Foundation

public struct HomepageDocument: Equatable {
    public var nodes: [HomepageNode]

    public init(nodes: [HomepageNode]) {
        self.nodes = nodes
    }
}

public enum HomepageAxis: Equatable {
    case vertical, horizontal
}

public enum HomepageAlignment: Equatable {
    case leading, center, trailing
}

public enum HomepageHintTheme: Equatable {
    case blue, yellow, red
}

public enum HomepageButtonStyle: Equatable {
    case normal, highlight, red
}

/// 主页事件（对应 EventType / EventData，以及 CustomEvent 列表）。
public enum HomepageEvent: Equatable {
    case openURL(URL)
    case message(title: String, content: String)
    case refresh
    /// 打开帮助条目（PCL 的帮助库没有接入）。
    case help(String)
    /// 启动指定实例。
    case launch(String)
    /// 切换顶栏页面（0 启动 / 1 下载 / 2 联机 / 3 设置 / 4 更多）。
    case switchPage(Int)
    /// 修改变量：页面内的 {variable:...} 与 Visibility 条件都用它。
    case setVariable(name: String, value: String)
}

/// 一段富文本。
public struct HomepageTextRun: Equatable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    /// 行内代码（对应 TextBox 的 InlineCode 样式）。
    public var code: Bool
    public var size: CGFloat?
    /// 颜色：十六进制值，或 brush:N（对应 PCL2 的 ColorBrushN）。
    public var color: String?
    public var link: URL?

    public init(
        text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        code: Bool = false,
        size: CGFloat? = nil,
        color: String? = nil,
        link: URL? = nil
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.code = code
        self.size = size
        self.color = color
        self.link = link
    }
}

/// 网格列宽：Auto / 星号都按弹性处理，固定像素保留数值。
public enum HomepageGridLength: Equatable {
    case flexible
    case fixed(CGFloat)
}

public struct HomepageGridCell: Equatable {
    public var row: Int
    public var column: Int
    public var columnSpan: Int
    public var rowSpan: Int
    public var node: HomepageNode

    public init(row: Int, column: Int, columnSpan: Int = 1, rowSpan: Int = 1, node: HomepageNode) {
        self.row = row
        self.column = column
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.node = node
    }
}

public indirect enum HomepageNode: Equatable {
    case stack(HomepageAxis, HomepageAlignment, [HomepageNode])
    case card(title: String?, foldable: Bool, folded: Bool, [HomepageNode])
    case richText([HomepageTextRun], alignment: HomepageAlignment)
    case hint(String, HomepageHintTheme)
    case button(String, HomepageButtonStyle, [HomepageEvent])
    case textButton(String, HomepageAlignment, [HomepageEvent])
    case image(source: String, height: CGFloat?, width: CGFloat?, alignment: HomepageAlignment)
    /// Grid：列宽 + 单元格。行高按内容自适应。
    case grid(columns: [HomepageGridLength], cells: [HomepageGridCell])
    /// WrapPanel：按可用宽度自动换行。
    case wrap([HomepageNode])
    /// Visibility="{variable:Name:Default}"：变量等于 Collapsed 时不渲染。
    case conditional(variable: String, defaultValue: String, HomepageNode)
}
