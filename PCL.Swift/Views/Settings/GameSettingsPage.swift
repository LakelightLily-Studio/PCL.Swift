//
//  GameSettingsPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/6.
//

import SwiftUI
import Core

/// 设置 → 游戏。
///
/// Java 运行时管理原先独占一个侧边栏条目（「Java 管理」），现在归到游戏页下：
/// Java 只服务于启动游戏，当作游戏配置比当作启动器的全局配置更贴合语义。
struct GameSettingsPage: View {
    @StateObject private var viewModel: JavaSettingsViewModel = .init()
    
    var body: some View {
        CardContainer {
            MyCard(nil) {
                HStack {
                    MyButton("刷新 Java 列表") {
                        do {
                            try JavaManager.shared.research()
                            hint("刷新成功！", type: .finish)
                        } catch {
                            err("刷新 Java 列表失败：\(error.localizedDescription)")
                            hint("刷新 Java 列表失败：\(error.localizedDescription)", type: .critical)
                        }
                    }
                    .frame(width: 120)
                    
                    MyButton("安装 Java") {
                        Task {
                            do {
                                let downloads: [MojangJavaList.JavaDownload] = try await viewModel.javaDownloads()
                                if let index: Int = await MessageBoxManager.shared.showListAsync(
                                    title: "选择 Java 版本",
                                    items: downloads.map(viewModel.listItem(forJavaDownload:))
                                ) {
                                    TaskManager.shared.execute(task: JavaInstallTask.create(download: downloads[index]))
                                    AppRouter.shared.append(.tasks)
                                }
                            } catch {
                                err("拉取 Java 列表失败：\(error.localizedDescription)")
                                hint("拉取 Java 列表失败：\(error.localizedDescription)", type: .critical)
                            }
                        }
                    }
                    .frame(width: 120)
                    
                    MyButton("手动添加 Java") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        panel.title = "选择 java 可执行文件"
                        
                        panel.begin { result in
                            guard result == .OK, let url = panel.url else { return }
                            do {
                                let runtime = try viewModel.addCustomRuntime(at: url)
                                hint("添加 \(runtime.description) 成功！", type: .finish)
                            } catch {
                                hint("添加 Java 失败：\(error.localizedDescription)", type: .critical)
                            }
                        }
                    }
                    .frame(width: 120)
                    
                    Spacer()
                }
                .frame(height: 40)
            }
            
            MyCard("Java 列表", folded: false) {
                VStack(spacing: 0) {
                    ForEach(0..<viewModel.javaList.count, id: \.self) { idx in
                        let item = viewModel.javaList[idx]
                        MyListItem { hovered in
                            HStack {
                                VStack(alignment: .leading) {
                                    MyText(item.name)
                                        .lineLimit(1)
                                    MyText(item.url.path, color: .colorGray3)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if item.isCustom && hovered {
                                    Image(systemName: "trash")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 12)
                                        .foregroundStyle(Color.color3)
                                        .padding(.trailing, 8)
                                        .contentShape(.rect)
                                        .onTapGesture {
                                            viewModel.removeCustomRuntime(at: item.url)
                                            hint("移除成功！", type: .finish)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .cardIndex(1)
        }
    }
}
