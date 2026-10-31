//
//  SetupWizardView.swift
//  PCL.Swift
//
//  首次启动的设置向导：欢迎 → 账号 → Java → 主题 → 完成。
//
//  设计上的几点取舍：
//  - 向导阶段顶栏就是启动器那块 48pt 主色栏，当前步骤的大标题显示在栏内；
//    页面内不再重复一份标题，标题左对齐，与启动器主体一致；
//  - 步骤条用数字 1–5，当前步用主题色填充、已完成步用浅一档；连线是连续进度条，
//    按步骤从左往右逐步填充，不是整段变色；
//  - 「跳过」只跳过当前这一步（进入下一步），最后一步换成「完成」；
//  - 完成页是独立的庆祝页：只保留居中「设置完成」、左下角彩带和底部「完成」；
//  - 账号/Java/主题都是可用的最小控件，不是占位卡片；只有「正版账号登录」
//    仍需要主界面侧边栏的设备码流程，这里给一句提示。
//

import SwiftUI
import Core

struct SetupWizardView: View {
    let onFinish: () -> Void

    @StateObject private var themeManager: ThemeManager = .shared
    @ObservedObject private var configObserver: LauncherConfigObserver = .shared
    @State private var step: Step = .welcome

    /// 账号视图模型：正版登录的设备码流程要复用它，因此向导阶段就建一个实例。
    /// 它自身把 `accounts` / `currentAccountId` 同步进 `LauncherConfig`。
    @StateObject private var accountVM: AccountViewModel = .init()
    /// 弹窗打开期间禁用「添加账户」，避免重复发起登录流程。
    @ObservedObject private var messageBoxManager: MessageBoxManager = .shared

    /// Java 运行时列表，随 `JavaManager` 一起刷新。
    @State private var javaRuntimes: [JavaRuntime] = JavaManager.shared.javaRuntimes
    @State private var researchingJava: Bool = false

    enum Step: Int, CaseIterable {
        case welcome, account, java, theme, done

        /// 步骤条上的短名。
        var title: String {
            switch self {
            case .welcome: "欢迎"
            case .account: "账号"
            case .java: "Java"
            case .theme: "主题"
            case .done: "完成"
            }
        }

        /// 顶栏里显示的大标题。欢迎步沿用原来的完整欢迎语。
        var pageTitle: String {
            switch self {
            case .welcome: "欢迎来到 PCL.Swift"
            case .account: "登录账号"
            case .java: "选择 Java"
            case .theme: "选择主题"
            case .done: "完成配置"
            }
        }

        var number: Int { rawValue + 1 }
    }

    var body: some View {
        ZStack {
            Color.colorBackground
            WizardGridBackground()

            // 完成页的彩带从窗口左下角喷出，画在内容下面，不挡按钮点击。
            if step == .done {
                ConfettiView()
            }

            VStack(spacing: 0) {
                titleBar
                VStack(alignment: .leading, spacing: 0) {
                    if step != .done {
                        WizardEntrance(index: 0) {
                            VStack(spacing: 0) {
                                stepIndicator
                                Divider()
                                    .padding(.top, 18)
                            }
                        }
                    }

                    WizardEntrance(index: 1, enabled: step != .done) {
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .id(step)
                    .padding(.top, step == .done ? 0 : 20)

                    WizardEntrance(index: 2) {
                        footer
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    // MARK: - 顶部标题栏

    /// 与启动器主体同一块 48pt 主色栏，只是内容换成当前步骤的大标题。
    ///
    /// 三色按钮由系统画在透明标题栏里，文字按 `trafficLightReservedWidth` 让开它们；
    /// 向导页里不再重复一份页面内标题。
    private var titleBar: some View {
        ZStack(alignment: .leading) {
            NavigationBarBackgroundView()
            // 「液态玻璃」是浅色的，白字看不清；与启动器标题栏同一套判断。
            MyText(
                step.pageTitle,
                size: 22,
                color: LauncherConfig.shared.navigationBarBackground == .liquidGlass ? .color1 : .white
            )
                .id(step)
                .transition(.opacity)
                .lineLimit(1)
                .padding(.leading, TitleBarView.trafficLightReservedWidth)
        }
        .frame(height: AppWindow.titleBarHeight)
    }

    // MARK: - 步骤条

    private var stepIndicator: some View {
        GeometryReader { proxy in
            let columnWidth: CGFloat = proxy.size.width / CGFloat(Step.allCases.count)
            let startX: CGFloat = columnWidth / 2
            let endX: CGFloat = proxy.size.width - columnWidth / 2
            let progress: CGFloat = CGFloat(step.rawValue) / CGFloat(Step.allCases.count - 1)

            ZStack(alignment: .topLeading) {
                // 底轨：从第一个圆心的位置画到最后一个圆心。
                Capsule()
                    .fill(Color.colorGray5)
                    .frame(width: max(0, endX - startX), height: 2)
                    .offset(x: startX, y: 11)

                // 进度：按当前步骤逐步填充，而不是整段一起变色。
                Capsule()
                    .fill(Color.color4)
                    .frame(width: max(0, (endX - startX) * progress), height: 2)
                    .offset(x: startX, y: 11)
                    .animation(.easeInOut(duration: 0.45), value: step)

                HStack(spacing: 0) {
                    ForEach(Step.allCases, id: \.self) { item in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(circleFill(for: item))
                                Text("\(item.number)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(item == step ? Color.white : (item.rawValue < step.rawValue ? Color.color2 : Color.colorGray3))
                            }
                            .frame(width: 24, height: 24)
                            .scaleEffect(item == step ? 1 : 0.92)

                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundStyle(item == step ? Color.color2 : Color.colorGray2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 44)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func circleFill(for item: Step) -> Color {
        if item == step { return .color3 }
        if item.rawValue < step.rawValue { return .color6 }
        return .colorGray6
    }

    // MARK: - 分步内容

    @ViewBuilder
    private var content: some View {
        Group {
            switch step {
            case .welcome: welcomeStep
            case .account: accountStep
            case .java: javaStep
            case .theme: themeStep
            case .done: doneStep
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("几步完成基础配置，之后随时可以在「设置」里修改。")
                .font(.system(size: 13))
                .foregroundStyle(Color.colorGray2)

            HStack(spacing: 18) {
                Image(.iconAppIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 6) {
                    Text("PCL.Swift")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.color1)
                    Text("Plain Craft Launcher 的 macOS 重构版")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.colorGray2)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("PCL.Swift 是 Plain Craft Launcher 的非官方 macOS 重构版，用 SwiftUI 重写了 PCL 的界面与核心流程，目标是在 Mac 上提供与 PCL 一致的使用体验。")
                    .fixedSize(horizontal: false, vertical: true)

                Text("它支持安装与启动原版游戏、Forge、NeoForge 与 Fabric，也支持从 Modrinth 与 CurseForge 下载模组、资源包、光影包和整合包；账号、Java、下载源等配置都可以在「设置」里随时调整。")
                    .fixedSize(horizontal: false, vertical: true)

                Text("当前版本仍处于开发阶段，部分功能尚未完成，遇到问题欢迎到 GitHub 仓库反馈。")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.colorGray2)
        }
    }

    // MARK: 账号

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if accountVM.accounts.isEmpty {
                Text("还没有任何账号。登录正版账号，或先加一个离线账号。")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.colorGray2)
            } else {
                VStack(spacing: 8) {
                    ForEach(accountVM.accounts, id: \.id) { account in
                        accountRow(account)
                    }
                }
            }

            HStack(spacing: 10) {
                MyButton("添加账户", type: .highlight, disabled: messageBoxManager.currentMessageBox != nil) {
                    addAccount()
                }
                .frame(width: 108, height: 26)

                Text("支持正版、第三方与离线账号")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.colorGray3)
            }
        }
    }

    /// 统一的「添加账户」入口：直接复用主界面那个选择验证类型的弹窗，
    /// 正版 / 第三方 / 离线三条路径都由 `AccountViewModel` 自己处理。
    private func addAccount() {
        accountVM.requestAddAccount()
    }

    private func accountRow(_ account: Account) -> some View {
        let isCurrent: Bool = account.id == accountVM.currentAccountId
        return HStack(spacing: 12) {
            Image(account.type == .offline ? .iconOfflineAccount : .iconMicrosoftAccount)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(isCurrent ? Color.color3 : Color.colorGray2)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.profile.name)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.color1)
                Text(account.localizedTypeName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.colorGray3)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("当前")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.color3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.color7, in: RoundedRectangle(cornerRadius: 4))
            } else {
                MyButton("设为当前") {
                    switchAccount(to: account)
                }
                .frame(width: 76, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.colorGray8, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }


    private func switchAccount(to account: Account) {
        accountVM.switchAccount(to: account)
    }

    // MARK: Java

    private var javaStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(javaRuntimes.isEmpty ? "没有检测到 Java 运行时。" : "已检测到 \(javaRuntimes.count) 个 Java 运行时：")
                    .font(.system(size: 13))
                    .foregroundStyle(javaRuntimes.isEmpty ? Color.colorGray2 : Color.color1)
                Spacer(minLength: 0)
                MyButton("重新检测", disabled: researchingJava) {
                    researchJava()
                }
                .frame(width: 92, height: 26)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(javaRuntimes, id: \.executableURL) { runtime in
                        HStack(spacing: 12) {
                            Image(.iconJava)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Color.color3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Java \(runtime.majorVersion) · \(runtime.type.description)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.color1)
                                Text(runtime.executableURL.path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.colorGray3)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Text(runtime.architecture.description)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.color4)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.colorGray8, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }

            if javaRuntimes.isEmpty {
                MyTip(text: "启动器会在 `/Library/Java/JavaVirtualMachines` 与常见安装位置里查找 Java；也可以稍后在「设置 → 游戏」里手动指定。", theme: .yellow)
            }
        }
    }

    private func researchJava() {
        researchingJava = true
        Task { @MainActor in
            do {
                try JavaManager.shared.research()
                javaRuntimes = JavaManager.shared.javaRuntimes
            } catch {
                err("重新检测 Java 失败：\(error.localizedDescription)")
                hint("重新检测 Java 失败：\(error.localizedDescription)", type: .critical)
            }
            researchingJava = false
        }
    }

    // MARK: 主题

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("导航栏背景")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.color1)
                MySelect(navigationBarBackgroundBinding, entries: NavigationBarBackground.allCases)
                    .frame(width: 160, height: 26)
                Spacer(minLength: 0)
            }

            Text("选一个主题色，点击立即生效。")
                .font(.system(size: 13))
                .foregroundStyle(Color.colorGray2)

            // 主题现在有 15 个，横排一行必然超出窗口——而这一行的最小宽度会
            // 反向撑大整个 VStack，把上面的步骤条和下面的按钮一起顶出窗口。
            // 所以改成自适应网格 + 纵向滚动：列数由可用宽度决定，
            // 宽度再窄也只会往下换行，不会横向溢出。
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        themeCard(theme)
                    }
                }
                .padding(.vertical, 2)
            }
            .alwaysShowScrollIndicators()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var navigationBarBackgroundBinding: Binding<NavigationBarBackground> {
        Binding(
            get: { LauncherConfig.shared.navigationBarBackground },
            set: { value in
                LauncherConfig.shared.navigationBarBackground = value
                configObserver.touch()
            }
        )
    }

    private func themeCard(_ theme: Theme) -> some View {
        let isCurrent: Bool = themeManager.current == theme
        // 整张色卡就是按钮：本窗口里 SwiftUI 原生 Button 收不到鼠标事件，
        // 用与 `MyButton` 相同的 DragGesture 接点击才可靠。
        return cardBody(theme, isCurrent: isCurrent)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in themeManager.set(theme) }
            )
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }

    private func cardBody(_ theme: Theme, isCurrent: Bool) -> some View {
        let palette: ThemePalette = ThemeManager.shared.palette(for: theme)
        return VStack(alignment: .leading, spacing: 0) {
            // 色卡：主色铺底 + 三档阶梯，直观呈现选中态与描边的观感。
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.primary)
                    .frame(height: 26)
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill([palette.tint, palette.soft, palette.faint][index])
                            .frame(height: 14)
                    }
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.background)
                    .frame(height: 18)
            }
            .padding(10)

            HStack(spacing: 6) {
                Text(theme.description)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.color1)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.color3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        // 宽度交给网格决定：写死 190 会让自适应列宽失效。
        .frame(maxWidth: .infinity)
        .background(Color.colorGray8, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? palette.primary : Color.clear, lineWidth: 2)
                // 描边层只是装饰：不关掉命中测试的话它会把整张卡片的点击吃掉。
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 完成

    private var doneStep: some View {
        CompletionTitle()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    // MARK: - 底部按钮

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .done {
                MyButton("跳过") {
                    advance()
                }
                .frame(width: 76, height: 28)
            }

            Spacer()

            if step != .welcome && step != .done {
                MyButton("上一步") {
                    goBack()
                }
                .frame(width: 96, height: 30)
            }

            MyButton(step == .done ? "完成" : "下一步", type: .highlight) {
                if step == .done {
                    onFinish()
                } else {
                    advance()
                }
            }
            .frame(width: 120, height: 30)
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = next
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            step = previous
        }
    }
}

/// 向导页里的分段入场动画：曲线、时长和错峰都复用启动器其他页面的 PageEntrance。
private struct WizardEntrance<Content: View>: View {
    let index: Int
    let enabled: Bool
    private let content: () -> Content

    @State private var appeared: Bool = false

    init(index: Int, enabled: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.index = index
        self.enabled = enabled
        self.content = content
    }

    var body: some View {
        content()
            .modifier(PageEntranceShape(progress: appeared ? 1 : 0, enabled: enabled))
            .animation(enabled ? PageEntrance.animation(for: index) : nil, value: appeared)
            .onAppear {
                guard !appeared else { return }
                appeared = true
            }
    }
}

/// 完成页中央的大标题：弹簧缩放入场，配合左下角喷出的彩带。
private struct CompletionTitle: View {
    @State private var appeared: Bool = false

    var body: some View {
        MyText("设置完成", size: 44, color: .color1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.82)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.08), value: appeared)
            .onAppear {
                guard !appeared else { return }
                appeared = true
            }
    }
}
