//
//  HomepageXAMLParser.swift
//  PCL.Swift.Core
//
//  把 PCL2 的主页 XAML 子集解析成 HomepageDocument。
//
//  先剥掉 XML 声明与 xmlns，再包一层带命名空间声明的根节点，用 XMLParser 建原始树，
//  最后翻译成文档节点。样式表、富文本、Grid/WrapPanel、变量与自定义事件都在这一层处理。
//

import Foundation

public enum HomepageXAMLParser {
    public enum ParseError: LocalizedError {
        case invalidXML(String)

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let message): "主页内容不是合法的 XAML：" + message
            }
        }
    }

    public static func parse(_ content: String) throws -> HomepageDocument {
        let root: Element = try parseTree(stripDeclarations(content))
        let styles: StyleSheet = .init(collecting: root)
        return HomepageDocument(nodes: convertChildren(of: root, styles: styles))
    }

    // MARK: - 预处理

    private static func stripDeclarations(_ content: String) -> String {
        var text: String = content
        text = text.replacingOccurrences(of: "<\\?xml[^>]*\\?>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "xmlns(:[A-Za-z]+)?=\"[^\"]*\"", with: "", options: .regularExpression)
        return text
    }

    // MARK: - XML 树

    fileprivate final class Element {
        let name: String
        let attributes: [String: String]
        var content: [Content] = []

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }

        var textContent: String {
            content.map { item in
                switch item {
                case .text(let text): return text
                case .element(let element): return element.textContent
                }
            }.joined()
        }

        var childElements: [Element] {
            content.compactMap { item in
                if case .element(let element) = item { return element }
                return nil
            }
        }
    }

    fileprivate indirect enum Content {
        case text(String)
        case element(Element)
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        private var stack: [Element] = []
        var root: Element?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            stack.append(.init(name: elementName, attributes: attributeDict))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].content.append(.text(string))
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard !stack.isEmpty, let text = String(data: CDATABlock, encoding: .utf8) else { return }
            stack[stack.count - 1].content.append(.text(text))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard let element = stack.popLast() else { return }
            if stack.isEmpty {
                root = element
            } else {
                stack[stack.count - 1].content.append(.element(element))
            }
        }
    }

    private static func parseTree(_ body: String) throws -> Element {
        let wrapped: String = """
        <HomepageRoot xmlns:local="urn:pcl-local" xmlns:x="urn:pcl-x" xmlns:sys="urn:pcl-sys" xmlns:core="urn:pcl-core" xmlns:corewpf="urn:pcl-corewpf" xmlns="urn:pcl-default">
        \(body)
        </HomepageRoot>
        """
        let parser: XMLParser = .init(data: Data(wrapped.utf8))
        let delegate: TreeBuilder = .init()
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw ParseError.invalidXML(parser.parserError?.localizedDescription ?? "未知错误")
        }
        return root
    }

    // MARK: - 样式表

    fileprivate struct TextStyle {
        var size: CGFloat?
        var color: String?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var code: Bool?

        mutating func merge(_ other: TextStyle) {
            if let size = other.size { self.size = size }
            if let color = other.color { self.color = color }
            if let bold = other.bold { self.bold = bold }
            if let italic = other.italic { self.italic = italic }
            if let underline = other.underline { self.underline = underline }
            if let code = other.code { self.code = code }
        }
    }

    fileprivate struct StyleSheet {
        private var named: [String: TextStyle] = [:]
        private var byType: [String: TextStyle] = [:]

        init(collecting element: Element) {
            walk(element)
        }

        mutating func walk(_ element: Element) {
            if element.name.lowercased() == "style" {
                var style: TextStyle = .init()
                for setter in element.childElements where setter.name.lowercased() == "setter" {
                    guard let property = setter.attributes["Property"], let value = setter.attributes["Value"] else { continue }
                    switch property {
                    case "FontSize":
                        if let number = Double(value) { style.size = CGFloat(number) }
                    case "Foreground":
                        style.color = colorToken(value)
                    case "FontWeight":
                        style.bold = value.lowercased().contains("bold")
                    case "FontStyle":
                        style.italic = value.lowercased().contains("italic")
                    case "TextDecorations":
                        style.underline = value.lowercased().contains("underline")
                    case "FontFamily":
                        style.code = value.lowercased().contains("consolas") || value.lowercased().contains("mono")
                    default:
                        break
                    }
                }
                if let key = element.attributes["x:Key"] {
                    named[key] = style
                } else if let target = element.attributes["TargetType"] {
                    byType[target.lowercased()] = style
                }
            }
            for child in element.childElements { walk(child) }
        }

        func style(for element: Element, inherited: TextStyle) -> TextStyle {
            var result: TextStyle = inherited
            if let implicitStyle = byType[element.name.lowercased()] { result.merge(implicitStyle) }
            if let reference = element.attributes["Style"], let key = resourceKey(reference), let style = named[key] {
                result.merge(style)
            }
            if let size = element.attributes["FontSize"].flatMap({ Double($0) }) {
                result.size = CGFloat(size)
            }
            if let color = element.attributes["Foreground"].flatMap(colorToken) {
                result.color = color
            }
            if let weight = element.attributes["FontWeight"] {
                result.bold = weight.lowercased().contains("bold")
            }
            if let decoration = element.attributes["TextDecorations"] {
                result.underline = decoration.lowercased().contains("underline")
            }
            switch element.name.lowercased() {
            case "bold": result.bold = true
            case "italic": result.italic = true
            case "underline": result.underline = true
            case "textbox": result.code = true
            default: break
            }
            return result
        }
    }

    // MARK: - 元素翻译

    private static func convertChildren(of element: Element, styles: StyleSheet) -> [HomepageNode] {
        element.childElements.flatMap { convert($0, styles: styles) }
    }

    private static func convert(_ element: Element, styles: StyleSheet) -> [HomepageNode] {
        let nodes: [HomepageNode] = convertCore(element, styles: styles)
        return wrapVisibility(nodes, attributes: element.attributes)
    }

    private static func convertCore(_ element: Element, styles: StyleSheet) -> [HomepageNode] {
        let name: String = element.name.lowercased()
        let attributes: [String: String] = element.attributes

        switch name {
        case "stackpanel":
            let axis: HomepageAxis = attributes["Orientation"]?.lowercased() == "horizontal" ? .horizontal : .vertical
            return [.stack(axis, alignment(attributes["HorizontalAlignment"]), convertChildren(of: element, styles: styles))]

        case "wrappanel":
            return [.wrap(convertChildren(of: element, styles: styles))]

        case "dockpanel":
            return [.stack(.vertical, alignment(attributes["HorizontalAlignment"]), convertChildren(of: element, styles: styles))]

        case "grid":
            return [grid(element, styles: styles)]

        case "local:mycard":
            let title: String? = attributes["Title"].map(cleanBlock).flatMap { $0.isEmpty ? nil : $0 }
            let foldable: Bool = attributes["CanSwap"]?.lowercased() == "true"
            let folded: Bool = foldable
                && (attributes["IsSwapped"]?.lowercased() == "true" || attributes["IsSwaped"]?.lowercased() == "true")
            return [.card(title: title, foldable: foldable, folded: folded, convertChildren(of: element, styles: styles))]

        case "local:myhint":
            let value: String = cleanBlock((attributes["Text"] ?? "") + element.textContent)
            guard !value.isEmpty else { return [] }
            let theme: HomepageHintTheme
            switch attributes["Theme"]?.lowercased() {
            case "yellow": theme = .yellow
            case "red": theme = .red
            default: theme = .blue
            }
            return [.hint(value, theme)]

        case "local:mybutton":
            let value: String = cleanBlock((attributes["Text"] ?? "") + element.textContent)
            guard !value.isEmpty else { return [] }
            return [.button(value, buttonStyle(attributes["ColorType"]), events(of: element))]

        case "local:mytextbutton", "local:myicontextbutton", "local:mylistitem", "local:myextratextbutton":
            let value: String = cleanBlock((attributes["Text"] ?? attributes["Title"] ?? "") + element.textContent)
            guard !value.isEmpty else { return [] }
            return [.textButton(value, alignment(attributes["HorizontalAlignment"]), events(of: element))]

        case "local:myiconbutton":
            let list: [HomepageEvent] = events(of: element)
            guard list.contains(where: { $0 == .refresh }) else { return [] }
            return [.textButton("刷新", .leading, [.refresh])]

        case "local:myimage":
            guard let source = attributes["Source"], !source.isEmpty else { return [] }
            guard source.hasPrefix("http") || source.hasPrefix("/") || source.hasPrefix("file:") else { return [] }
            let height: CGFloat? = attributes["Height"].flatMap { Double($0) }.map { CGFloat($0) }
            let width: CGFloat? = attributes["Width"].flatMap { Double($0) }.map { CGFloat($0) }
            return [.image(
                source: source,
                height: height,
                width: width,
                alignment: alignment(attributes["HorizontalAlignment"])
            )]

        case "textblock", "paragraph", "listitem", "run", "bold", "italic", "underline", "hyperlink", "textbox", "linebreak":
            let textStyle: TextStyle = styles.style(for: element, inherited: .init())
            var runs: [HomepageTextRun] = []
            collectRuns(of: element, styles: styles, inherited: textStyle, into: &runs)
            trimRuns(&runs)
            guard !runs.isEmpty else { return [] }
            return [.richText(runs, alignment: alignment(attributes["HorizontalAlignment"]))]

        case "style", "setter", "controltemplate", "resourcedictionary", "stackpanel.resources",
             "grid.resources", "grid.columndefinitions", "grid.rowdefinitions",
             "sys:string", "sys:double", "sys:boolean", "x:array",
             "local:customservice.events", "local:customeventservice.events", "local:customeventcollection", "local:customevent":
            return []

        default:
            return convertChildren(of: element, styles: styles)
        }
    }

    // MARK: - Grid

    private static func grid(_ element: Element, styles: StyleSheet) -> HomepageNode {
        var columns: [HomepageGridLength] = []
        for child in element.childElements where child.name.lowercased().hasSuffix("columndefinitions") {
            columns = child.childElements
                .filter { $0.name.lowercased().hasSuffix("columndefinition") }
                .map { gridLength($0.attributes["Width"]) }
        }
        if columns.isEmpty { columns = [.flexible] }

        var cells: [HomepageGridCell] = []
        for child in element.childElements {
            let childName: String = child.name.lowercased()
            if childName.hasSuffix("definitions") || childName.hasSuffix("resources") { continue }
            let row: Int = child.attributes["Grid.Row"].flatMap(Int.init) ?? 0
            let column: Int = child.attributes["Grid.Column"].flatMap(Int.init) ?? 0
            let columnSpan: Int = child.attributes["Grid.ColumnSpan"].flatMap(Int.init) ?? 1
            let rowSpan: Int = child.attributes["Grid.RowSpan"].flatMap(Int.init) ?? 1
            let nodes: [HomepageNode] = convert(child, styles: styles)
            guard !nodes.isEmpty else { continue }
            let node: HomepageNode = nodes.count == 1 ? nodes[0] : .stack(.vertical, .leading, nodes)
            cells.append(.init(row: row, column: column, columnSpan: columnSpan, rowSpan: rowSpan, node: node))
        }
        return .grid(columns: columns, cells: cells)
    }

    private static func gridLength(_ raw: String?) -> HomepageGridLength {
        guard let raw, !raw.isEmpty else { return .flexible }
        if raw.lowercased() == "auto" || raw.contains("*") { return .flexible }
        if let number = Double(raw) { return .fixed(CGFloat(number)) }
        return .flexible
    }

    // MARK: - 富文本

    private static func collectRuns(
        of element: Element,
        styles: StyleSheet,
        inherited: TextStyle,
        into runs: inout [HomepageTextRun]
    ) {
        let style: TextStyle = styles.style(for: element, inherited: inherited)
        let elementName: String = element.name.lowercased()

        for item in element.content {
            switch item {
            case .text(let raw):
                let text: String = cleanInline(raw)
                guard !text.isEmpty else { continue }
                runs.append(makeRun(text, style))

            case .element(let child):
                let childName: String = child.name.lowercased()
                switch childName {
                case "local:mytextbutton", "local:myicontextbutton":
                    let label: String = cleanInline((child.attributes["Text"] ?? "") + child.textContent)
                    guard !label.isEmpty else { continue }
                    var childStyle: TextStyle = styles.style(for: child, inherited: style)
                    childStyle.underline = true
                    var link: URL?
                    if case .openURL(let url)? = singleEvent(child.attributes) { link = url }
                    runs.append(makeRun(label, childStyle, link: link))
                case "linebreak":
                    runs.append(makeRun("\n", style))
                case "textbox":
                    let label: String = cleanInline(child.textContent)
                    guard !label.isEmpty else { continue }
                    runs.append(makeRun(label, styles.style(for: child, inherited: style)))
                default:
                    collectRuns(of: child, styles: styles, inherited: style, into: &runs)
                }
            }
        }

        if runs.isEmpty, let attribute = element.attributes["Text"] {
            let text: String = cleanBlock(attribute)
            if !text.isEmpty, elementName == "textblock" || elementName == "paragraph" {
                runs.append(makeRun(text, style))
            }
        }
    }

    private static func makeRun(_ text: String, _ style: TextStyle, link: URL? = nil) -> HomepageTextRun {
        .init(
            text: text,
            bold: style.bold ?? false,
            italic: style.italic ?? false,
            underline: style.underline ?? false,
            code: style.code ?? false,
            size: style.size,
            color: style.color,
            link: link
        )
    }

    private static func trimRuns(_ runs: inout [HomepageTextRun]) {
        guard !runs.isEmpty else { return }
        runs[0].text = runs[0].text.replacingOccurrences(of: "^ +", with: "", options: .regularExpression)
        let last: Int = runs.count - 1
        runs[last].text = runs[last].text.replacingOccurrences(of: " +$", with: "", options: .regularExpression)
        runs.removeAll { $0.text.isEmpty }
    }

    // MARK: - 变量与事件

    /// 解析 {variable:Name:Default} 形式的属性值。
    private static func variableToken(_ raw: String) -> (name: String, defaultValue: String)? {
        guard let match = raw.range(of: "\\{variable:([^:}]+):([^}]*)\\}", options: .regularExpression) else {
            return nil
        }
        let inner: String = String(String(raw[match]).dropFirst("{variable:".count).dropLast())
        let parts: [String] = inner.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    private static func wrapVisibility(_ nodes: [HomepageNode], attributes: [String: String]) -> [HomepageNode] {
        guard let raw = attributes["Visibility"], let token = variableToken(raw) else { return nodes }
        return nodes.map { .conditional(variable: token.name, defaultValue: token.defaultValue, $0) }
    }

    private static func events(of element: Element) -> [HomepageEvent] {
        var result: [HomepageEvent] = []
        if let event = singleEvent(element.attributes) { result.append(event) }
        for container in element.childElements {
            let name: String = container.name.lowercased()
            guard name.hasSuffix("customeventservice.events") || name.hasSuffix("customeventcollection") else { continue }
            for item in container.childElements where item.name.lowercased().hasSuffix("customevent") {
                guard let type = item.attributes["Type"] else { continue }
                let data: String = item.attributes["Data"] ?? ""
                switch type {
                case "修改变量":
                    let parts: [String] = data.components(separatedBy: "|")
                    if parts.count >= 2 {
                        result.append(.setVariable(name: parts[0], value: parts[1]))
                    }
                case "刷新页面":
                    result.append(.refresh)
                case "打开网页":
                    if let url = URL(string: data) { result.append(.openURL(url)) }
                case "弹出窗口":
                    let parts: [String] = data.components(separatedBy: "|")
                    result.append(.message(title: cleanBlock(parts.first ?? "提示"), content: cleanBlock(parts.dropFirst().joined(separator: "|"))))
                case "打开帮助":
                    result.append(.help(data))
                case "启动游戏":
                    result.append(.launch(data))
                case "切换页面":
                    let index: Int = Int(data.components(separatedBy: "|").first ?? "") ?? 0
                    result.append(.switchPage(index))
                default:
                    break
                }
            }
        }
        return result
    }

    private static func singleEvent(_ attributes: [String: String]) -> HomepageEvent? {
        guard let type = attributes["EventType"] else { return nil }
        let data: String = attributes["EventData"] ?? ""
        switch type {
        case "打开网页":
            guard let url = URL(string: data.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return .openURL(url)
        case "弹出窗口":
            let parts: [String] = data.components(separatedBy: "|")
            return .message(
                title: cleanBlock(parts.first ?? "提示"),
                content: cleanBlock(parts.dropFirst().joined(separator: "|"))
            )
        case "刷新主页":
            return .refresh
        case "打开帮助":
            return .help(data)
        case "启动游戏":
            return .launch(data)
        case "切换页面":
            return .switchPage(Int(data.components(separatedBy: "|").first ?? "") ?? 0)
        default:
            return nil
        }
    }

    // MARK: - 属性解析

    private static func alignment(_ raw: String?) -> HomepageAlignment {
        switch raw?.lowercased() {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }

    private static func buttonStyle(_ raw: String?) -> HomepageButtonStyle {
        switch raw?.lowercased() {
        case "highlight": .highlight
        case "red": .red
        default: .normal
        }
    }

    private static func colorToken(_ raw: String) -> String? {
        let value: String = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { return value }
        if let key = resourceKey(value) {
            if key.hasPrefix("ColorBrush"), let index = Int(key.dropFirst("ColorBrush".count)) {
                return "brush:\(index)"
            }
        }
        return nil
    }

    private static func resourceKey(_ raw: String) -> String? {
        guard let match = raw.range(of: "(?:Static|Dynamic)Resource\\s+([^}\\s]+)", options: .regularExpression) else { return nil }
        return String(raw[match].split(separator: " ").last ?? "")
    }

    // MARK: - 文本清洗

    /// 行内文本：压空白，保留 {variable:...} / {hint} / {cave} 这类占位，其余花括号清除。
    private static func cleanInline(_ raw: String) -> String {
        var text: String = raw
        text = text.replacingOccurrences(of: "\\{(?!variable:|hint\\}|cave\\})[^}]*\\}", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return text
    }

    private static func cleanBlock(_ raw: String) -> String {
        var text: String = raw
        text = text.replacingOccurrences(of: "\\{(?!variable:|hint\\}|cave\\})[^}]*\\}", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
