//
//  LaunchSettingsTests.swift
//  PCL.Swift.Tests
//
//  启动设置里那些"纯规则"的回归测试。
//

import Testing
import Foundation
import Core

struct LaunchVisibilityTests {
    @Test("没有实例覆盖值时，可见性跟随全局默认")
    func fallsBackToGlobal() {
        LauncherConfigDefaults.launcherVisibility = .minimize
        defer { LauncherConfigDefaults.launcherVisibility = .keepVisible }
        #expect(LauncherVisibility.resolve(instance: nil) == .minimize)
    }

    @Test("枚举的 rawValue 稳定，改动会让旧配置解码失败")
    func rawValuesAreStable() {
        // 这些字符串会写进 config.json 与实例的 .clconfig.json，
        // 改名等于让所有老配置静默回落到默认值。
        #expect(GameWindowType.standard.rawValue == "standard")
        #expect(GameWindowType.fullscreen.rawValue == "fullscreen")
        #expect(GameWindowType.custom.rawValue == "custom")
        #expect(LauncherVisibility.keepVisible.rawValue == "keepVisible")
        #expect(ProcessPriority.normal.rawValue == "normal")
    }

    @Test("实例配置里的新字段缺省时全部为 nil（表示跟随全局）")
    func newConfigFieldsDefaultToNil() throws {
        let json: String = """
        {"jvmHeapSize": 4096}
        """
        let config: MinecraftInstance.Config = try JSONDecoder().decode(
            MinecraftInstance.Config.self,
            from: Data(json.utf8)
        )
        #expect(config.gameWindowTitle == nil)
        #expect(config.gameWindowType == nil)
        #expect(config.gameWindowWidth == nil)
        #expect(config.launcherVisibility == nil)
        #expect(config.processPriority == nil)
        #expect(config.prelaunchCommand == nil)
        #expect(config.gameArguments == nil)
        #expect(config.memoryOptimize == nil)
    }

    @Test("实例配置能往返编码，新字段不丢")
    func configRoundTrips() throws {
        var config: MinecraftInstance.Config = .init(jvmHeapSize: 2048, javaURL: nil)
        config.gameWindowTitle = "我的世界"
        config.gameWindowType = .custom
        config.gameWindowWidth = 1280
        config.gameWindowHeight = 720
        config.launcherVisibility = .hide
        config.processPriority = .high
        config.prelaunchCommand = "echo hi"
        config.gameArguments = ["--server", "example.com"]
        config.memoryOptimize = true

        let data: Data = try JSONEncoder().encode(config)
        let decoded: MinecraftInstance.Config = try JSONDecoder().decode(
            MinecraftInstance.Config.self,
            from: data
        )
        #expect(decoded.gameWindowTitle == "我的世界")
        #expect(decoded.gameWindowType == .custom)
        #expect(decoded.gameWindowWidth == 1280)
        #expect(decoded.launcherVisibility == .hide)
        #expect(decoded.processPriority == .high)
        #expect(decoded.gameArguments == ["--server", "example.com"])
        #expect(decoded.memoryOptimize == true)
    }
}
