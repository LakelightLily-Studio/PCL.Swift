//
//  AboutPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/1/7.
//

import SwiftUI
import Core

struct AboutPage: View {
    var body: some View {
        CardContainer {
            StaticCard("关于") {
                VStack(spacing: 0) {
                    ProfileView(.init("LTCatt", fallback: .ltCatt), "龙腾猫跃", "Plain Craft Launcher 的作者！",
                                .init("GitHub 主页", "https://github.com/LTCatt"),
                                .init("前往赞助", "https://afdian.com/a/LTCat"))
                    
                    ProfileView(.init("Functy", fallback: .functy), "Functy", "PCL.Swift 的作者",
                                .init("GitHub 主页", "https://github.com/functy23"))
                    
                    ProfileView(.init("LakelightLily", fallback: .lakelightLily), "LakelightLily Studio", "PCL.Swift 的开发团队",
                                .init("GitHub 主页", "https://github.com/LakelightLily-Studio"))
                    
                    ProfileView(.init("PCLMac", fallback: .pclMac), "PCL.Swift", "当前版本：\(Metadata.appVersion) (\(Metadata.bundleVersion))",
                                .init("GitHub 仓库", "https://github.com/LakelightLily-Studio/PCL.Swift"),
                                .init("问题反馈", "https://github.com/LakelightLily-Studio/PCL.Swift/issues"))
                }
            }
            // 卡片序号必须从 0 连续排下去：入场动画的延迟是 25ms × index（封顶 8 步）。
            // 早先「关于」是 1、「特别鸣谢」是 2，而最后一张卡没写 index（默认 0），
            // 于是「许可与版权声明」抢在「特别鸣谢」前面出现，看起来就是后者慢了一步。
            .cardIndex(0)
            
            StaticCard("特别鸣谢") {
                VStack(spacing: 0) {
                    ProfileView(.init("PCLCommunity", fallback: .pclCommunity), "PCL Community", "Plain Craft Launcher 非官方社区",
                                .init("GitHub 主页", "https://github.com/PCL-Community"))
                    
                    ProfileView(.init("PCLProto", fallback: .pclProto), "PCL.Proto", "以 PCL2 和 PCL2-CE 为蓝本，旨在为各 PCL 分支版本提供一个标准化的原型样本。",
                                .init("GitHub 仓库", "https://github.com/PCL-Community/PCL.Proto"))
                    
                    ProfileView(.init("bangbang93", fallback: .bangbang93), "bangbang93", "提供 BMCLAPI 镜像源，详见 https://bmclapi.bangbang93.com",
                                .init("前往赞助", "https://afdian.com/a/bangbang93"))

                    ProfileView(.init("SwiftCraftLauncher", fallback: .swiftCraftLauncher), "Swift Craft Launcher", "感谢 SCL 开发团队与我们的持续交流与相互启发。",
                                .init("GitHub 仓库", "https://github.com/suhang12332/Swift-Craft-Launcher"))
                }
            }
            .cardIndex(1)
            
            StaticCard("许可与版权声明") {
                VStack(spacing: 15) {
                    LicenseListItem(
                        "SwiftyJSON", "Copyright (c) 2017 Ruoyu Fu\nLicensed under the MIT License.",
                        sourceURL: "https://github.com/SwiftyJSON/SwiftyJSON",
                        licenseURL: "https://github.com/SwiftyJSON/SwiftyJSON/blob/master/LICENSE"
                    )
                    LicenseListItem(
                        "ZIPFoundation", "Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)\nLicensed under the MIT License.",
                        sourceURL: "https://github.com/weichsel/ZIPFoundation",
                        licenseURL: "https://github.com/weichsel/ZIPFoundation/blob/development/LICENSE"
                    )
                    LicenseListItem(
                        "SwiftScaffolding", "Copyright (c) 2025-2026 CylorineStudio\nLicensed under the MIT License.",
                        sourceURL: "https://github.com/CylorineStudio/SwiftScaffolding",
                        licenseURL: "https://github.com/CylorineStudio/SwiftScaffolding/blob/main/LICENSE"
                    )
                    LicenseListItem(
                        "TOMLDecoder", "Copyright (c) 2019 TOMLDecoder contributors\nLicensed under the MIT License.",
                        sourceURL: "https://github.com/dduan/TOMLDecoder",
                        licenseURL: "https://github.com/dduan/TOMLDecoder/blob/main/LICENSE"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .cardIndex(2)
        }
    }
    
    private struct ProfileView: View {
        @ObservedObject private var easterEggManager: EasterEggManager = .shared
        @Environment(\.disableHoverAnimation) private var cardAppearAnimationPlaying: Bool
        
        private let avatar: Avatar
        private let nickname: String
        private let description: String
        private let links: [Link]
        
        init(_ avatar: Avatar, _ nickname: String, _ description: String, _ links: Link...) {
            self.avatar = avatar
            self.nickname = nickname
            self.description = description
            self.links = links
        }
        
        var body: some View {
            MyListItem {
                HStack {
                    // 头像托管在国内分发仓库，换图不用发版；仓库不可达时显示内置的同一张。
                    DomesticImage(avatar.name, fallback: avatar.fallback)
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .clipShape(.circle)
                    // 彩蛋的反色只在真正触发时才挂：.contrast(1) 看似无效果，但它仍会为每个头像
                    // 建立一层离屏合成。关于页有 8 个头像，切页时这 8 层是 AboutPage 慢的主因。
                    .modifier(AvatarContrast(inverted: easterEggManager.modifyColor))
                    VStack(alignment: .leading, spacing: 2) {
                        MyText(nickname)
                        MyText(description, color: .colorGray3)
                    }
                    Spacer()
                    HStack {
                        ForEach(links, id: \.url) { link in
                            MyButton(link.buttonName) {
                                if let url: URL = .init(string: link.url) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .padding(2)
            }
        }
        
        struct Link {
            let buttonName: String
            let url: String
            
            init(_ buttonName: String, _ url: String) {
                self.buttonName = buttonName
                self.url = url
            }
        }
        
        /// 头像。`name` 是国内分发仓库里的文件名（与 Assets.xcassets 的 imageset 同名），
        /// `fallback` 是打包进 App 的兜底图。
        struct Avatar {
            let name: String
            let fallback: ImageResource
            
            init(_ name: String, fallback: ImageResource) {
                self.name = name
                self.fallback = fallback
            }
        }
    }
    
    private struct LicenseListItem: View {
        private let name: String
        private let info: String
        private let sourceURL: URL
        private let licenseURL: URL
        
        init(_ name: String, _ info: String, sourceURL: String, licenseURL: String) {
            self.name = name
            self.info = info
            self.sourceURL = URL(string: sourceURL)!
            self.licenseURL = URL(string: licenseURL)!
        }
        
        var body: some View {
            HStack(alignment: .top, spacing: 20) {
                MyText(name)
                    .frame(width: 120, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    MyText(info)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 20) {
                        MyButton("查看来源网站") {
                            NSWorkspace.shared.open(sourceURL)
                        }
                        .frame(width: 140)
                        MyButton("查看许可文档") {
                            NSWorkspace.shared.open(licenseURL)
                        }
                        .frame(width: 140)
                    }
                    .frame(height: 38)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// 头像的反色效果，仅在彩蛋触发时挂载。
private struct AvatarContrast: ViewModifier {
    let inverted: Bool

    func body(content: Content) -> some View {
        if inverted {
            content.contrast(-1)
        } else {
            content
        }
    }
}
