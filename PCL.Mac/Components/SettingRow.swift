//
//  SettingRow.swift
//  PCL.Mac
//

import SwiftUI

/// 设置页里"标签 + 控件"的一行布局：标签定宽左对齐，控件占满剩余宽度。
///
/// 此前三个页面各自复制了一份同样的实现，只有标签宽度与纵向内边距不同，
/// 布局意图变更必须同步三处；合并后由参数区分。
struct SettingRow<Content: View>: View {
    private let label: String
    private let labelWidth: CGFloat
    private let verticalPadding: CGFloat
    private let content: Content

    init(
        _ label: String,
        labelWidth: CGFloat = 120,
        verticalPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.labelWidth = labelWidth
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 20) {
            MyText(label)
                .frame(width: labelWidth, alignment: .leading)
            HStack {
                Spacer(minLength: 0)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, verticalPadding)
    }
}
