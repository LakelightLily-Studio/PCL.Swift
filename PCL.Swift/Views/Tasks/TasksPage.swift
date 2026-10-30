//
//  TasksPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/9.
//

import SwiftUI
import Core

struct TasksPage: View {
    @ObservedObject private var taskManager: TaskManager = .shared
    @StateObject private var loadingVM: MyLoadingViewModel = .init(text: "没有正在执行的任务")
    
    var body: some View {
        CardContainer {
            if taskManager.tasks.isEmpty {
                MyLoading(viewModel: loadingVM)
            } else {
                ForEach(taskManager.tasks.filter(\.display)) { task in
                    TaskCard(task)
                        // 任务结束时卡片淡出并缩到 0.92 后再移除（PCL2 的 MyCard.AniDispose）。
                        // 插入不做过渡：卡片自己的入场动画已经管了那一段。
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        ))
                }
                // 只在任务增删时驱动过渡：进度更新（tasks 内的 @Published）不触发。
                .animation(.easeOut(duration: 0.2), value: taskManager.tasks.map(\.id))
            }
        }
    }
}

private struct TaskCard: View {
    @ObservedObject private var task: AnyMyTask
    
    init(_ task: AnyMyTask) {
        self.task = task
    }
    
    var body: some View {
        MyCard(task.name, foldable: false) {
            VStack(alignment: .leading) {
                ForEach(task.subTasks, id: \.name) { subTask in
                    HStack {
                        Group {
                            if subTask.state == .executing {
                                MyText("\(Int(subTask.progress * 100))%", color: .color2)
                            } else {
                                Image(subTask.state.icon)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(Color.color2)
                                    .frame(width: 20)
                            }
                        }
                        .frame(width: 40, height: 10)
                        MyText(subTask.name)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } action: {
            Image(.btnCancel)
                .resizable()
                .scaledToFit()
                .frame(height: 10)
                .foregroundStyle(Color.color2)
                .contentShape(.rect)
                .onTapGesture {
                    TaskManager.shared.cancel(task.id)
                    hint("已请求取消任务 \(task.name)！", type: .finish)
                }
        }
    }
}
