//
//  MySelect.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/7/8.
//

import SwiftUI

struct MySelect<Entry: Hashable & CustomStringConvertible>: View {
    @State private var hovered: Bool = false
    @State private var presented: Bool = false
    @State private var panel: SelectPanel?
    /// 控件在窗口内的位置。只在布局真正变化时更新，且只做一次结构体赋值——
    /// 早先这里每次变化都调 close() + 查 NSApplication.windows，卡片入场动画
    /// 期间每帧都会触发，是设置页卡顿的主要来源。
    @State private var globalFrame: CGRect = .zero
    @State private var height: CGFloat = 26
    @State private var observer: NSObjectProtocol?
    /// 控件所在的窗口。由 GeometryReader 的 background 里取，避免
    /// NSApplication.windows.first 在多窗口时拿错。
    @State private var hostWindow: NSWindow?
    
    @Binding private var selected: Entry
    
    private let entries: [Entry]
    /// 条目图标：返回 Assets.xcassets 里 imageset 的名字，没有图标就返回 nil。
    ///
    /// 用字符串而不是 ImageResource：这里要按条目动态取图，而 ImageResource 的 name
    /// 是 fileprivate，拼不出来；Image(name: String) 同样走资源目录，效果一致。
    private let icon: ((Entry) -> String?)?
    
    init(_ selected: Binding<Entry>, entries: [Entry], icon: ((Entry) -> String?)? = nil) {
        self._selected = selected
        self.entries = entries
        self.icon = icon
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                Color.clear
                    .background {
                        WindowAccessor { window in
                            // 必须判重：updateNSView 每次布局都会回调，
                            // 无条件写 @State 会让"布局 → 写状态 → 再布局"无限循环。
                            // 这是设置页/实例设置页卡顿的主因。
                            if hostWindow !== window {
                                hostWindow = window
                            }
                        }
                    }
                    .onAppear {
                        globalFrame = proxy.frame(in: .global)
                        height = proxy.size.height
                    }
                    .onChange(of: proxy.frame(in: .global)) { newFrame in
                        // 只记录，不查窗口、不关弹窗：真正的 rect 在打开时才算。
                        globalFrame = newFrame
                        height = proxy.size.height
                    }
            }
            
            // 底色拆成两层：恒定的半透明白 + 只动不透明度的主题色。
            // 早先是「悬停 color7 / 平时 white.opacity(0.5)」二选一，
            // 两端的色相与透明度同时变化，过渡中间会发灰。
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.cardBackground.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.color7.opacity(hovered ? 1 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(foregroundColor, lineWidth: 1.5, antialiased: false)
                }
                .allowsHitTesting(false)
            
            HStack(spacing: 6) {
                if let iconName = icon?(selected) {
                    Image(iconName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(.leading, 2)
                }
                MyText(selected.description)
                
                Spacer(minLength: 0)
                
                Image(.btnFold)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8)
                    .rotationEffect(.degrees(presented ? -180 : 0), anchor: .center)
                    .animation(.spring(response: 0.35), value: presented)
                    .foregroundStyle(foregroundColor)
                    .padding(.trailing, 2)
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 26)
        .contentShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture {
            presented.toggle()
        }
        .onHover { hovered = $0 }
        .animation(.linear(duration: 0.1), value: hovered)
        .onChange(of: presented) { newValue in
            close()
            if newValue {
                let hostingView = NSHostingView(rootView: PopupView(
                    entries: entries,
                    selectedEntry: selected,
                    icon: icon
                ) { entry in
                    selected = entry
                    presented = false
                    close()
                })
                
                let panel = SelectPanel(
                    contentRect: popupRect(),
                    styleMask: [],
                    backing: .buffered,
                    defer: false
                )
                panel.contentView = hostingView
                panel.backgroundColor = .clear
                panel.hidesOnDeactivate = true
                
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: panel,
                    queue: .main
                ) { _ in
                    self.presented = false
                    self.close()
                }
                
                panel.makeKeyAndOrderFront(nil)
                
                self.panel = panel
            }
        }
        .onDisappear {
            close()
        }
    }
    
    private var foregroundColor: Color {
        hovered ? .color4 : .color5
    }
    
    private func close() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        panel?.close()
        panel = nil
    }
    
    /// 计算弹出面板的屏幕坐标。只在打开时调用一次。
    private func popupRect() -> NSRect {
        guard let window = hostWindow ?? NSApplication.shared.windows.first,
              let contentView = window.contentView else { return .zero }

        let contentHeight: CGFloat = contentView.bounds.height
        let popupHeight: CGFloat = height * min(CGFloat(entries.count), 5.5)
        let rectInWindow = NSRect(
            x: globalFrame.minX,
            y: contentHeight - (globalFrame.minY - 1) - height - popupHeight,
            width: globalFrame.width,
            height: popupHeight
        )
        return window.convertToScreen(rectInWindow)
    }
}

private struct PopupView<Entry: Hashable & CustomStringConvertible>: View {
    @State private var hoveredEntry: Entry?
    private let entries: [Entry]
    private let selectedEntry: Entry
    private let icon: ((Entry) -> String?)?
    private let onSelect: (Entry) -> Void
    
    init(
        entries: [Entry],
        selectedEntry: Entry,
        icon: ((Entry) -> String?)?,
        onSelect: @escaping (Entry) -> Void
    ) {
        self.entries = entries
        self.selectedEntry = selectedEntry
        self.icon = icon
        self.onSelect = onSelect
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.cardBackground)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.self) { entry in
                        Group {
                            HStack(spacing: 6) {
                                if let iconName = icon?(entry) {
                                    Image(iconName)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                }
                                MyText(entry.description)
                            }
                            .padding(.leading, 6)
                        }
                        .frame(height: 26)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        // 同一条规矩：未悬停用 color7 的 0 不透明度，不要 .clear，
                        // 否则淡出时会先经过一段灰。
                        .background(
                            selectedEntry == entry
                                ? Color.color6
                                : Color.color7.opacity(hoveredEntry == entry ? 1 : 0)
                        )
                        .onTapGesture {
                            onSelect(entry)
                        }
                        .onHover { hovered in
                            if hovered {
                                hoveredEntry = entry
                            } else if hoveredEntry == entry {
                                hoveredEntry = nil
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.color4, lineWidth: 1.5, antialiased: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: hoveredEntry)
    }
}

/// 取当前视图所在的 NSWindow。
///
/// SwiftUI 没有直接暴露窗口的 API，标准做法是在 background 里塞一个
/// 只做转发的 NSViewRepresentable。
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view: NSView = .init()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 只在窗口真的换了才回调。原来的实现每次布局都异步回调一次，
        // 而上层收到回调会写 @State，进而触发下一次布局——形成循环。
        let current: NSWindow? = nsView.window
        guard current !== context.coordinator.lastWindow else { return }
        context.coordinator.lastWindow = current
        onWindow(current)
    }

    func makeCoordinator() -> Coordinator { .init() }

    final class Coordinator {
        var lastWindow: NSWindow?
    }
}

private class SelectPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

#Preview {
    MySelect(.constant("entry0"), entries: Array(0..<10).map { "entry\($0)" })
        .padding()
}
