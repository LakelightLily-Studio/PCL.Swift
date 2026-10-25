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
        #expect(config.gameWindowType == nil)
        #expect(config.gameWindowWidth == nil)
        #expect(config.launcherVisibility == nil)
        #expect(config.processPriority == nil)
        #expect(config.prelaunchCommand == nil)
        #expect(config.gameArguments == nil)
    }

    @Test("实例配置能往返编码，新字段不丢")
    func configRoundTrips() throws {
        var config: MinecraftInstance.Config = .init(jvmHeapSize: 2048, javaURL: nil)
        config.gameWindowType = .custom
        config.gameWindowWidth = 1280
        config.gameWindowHeight = 720
        config.launcherVisibility = .hide
        config.processPriority = .high
        config.prelaunchCommand = "echo hi"
        config.gameArguments = ["--server", "example.com"]

        let data: Data = try JSONEncoder().encode(config)
        let decoded: MinecraftInstance.Config = try JSONDecoder().decode(
            MinecraftInstance.Config.self,
            from: data
        )
        #expect(decoded.gameWindowType == .custom)
        #expect(decoded.gameWindowWidth == 1280)
        #expect(decoded.launcherVisibility == .hide)
        #expect(decoded.processPriority == .high)
        #expect(decoded.gameArguments == ["--server", "example.com"])
    }
}

struct GarbageCollectorTests {
    @Test("「不指定」不产生任何参数，完全交给用户")
    func unspecifiedProducesNothing() {
        #expect(GarbageCollectorArguments.arguments(for: .unspecified, javaMajorVersion: 21).isEmpty)
    }

    @Test("自动 ZGC 按 Java 版本回落到 G1GC")
    func autoZGCFallsBackToG1() {
        // Java 8 上 ZGC 根本不存在，必须落到 G1GC，否则游戏起不来。
        let java8: [String] = GarbageCollectorArguments.arguments(for: .autoZGC, javaMajorVersion: 8)
        #expect(java8.contains("-XX:+UseG1GC"))
        #expect(!java8.contains("-XX:+UseZGC"))

        // Java 17 有非分代 ZGC，但没有分代 ZGC。
        let java17: [String] = GarbageCollectorArguments.arguments(for: .autoZGC, javaMajorVersion: 17)
        #expect(java17.contains("-XX:+UseZGC"))
        #expect(!java17.contains("-XX:+ZGenerational"))

        // Java 21 才有分代 ZGC。
        let java21: [String] = GarbageCollectorArguments.arguments(for: .autoZGC, javaMajorVersion: 21)
        #expect(java21.contains("-XX:+UseZGC"))
        #expect(java21.contains("-XX:+ZGenerational"))
    }

    @Test("「尽量使用分代 ZGC」在 Java 20 之前用 G1GC")
    func generationalZGCChecksVersion() {
        #expect(GarbageCollectorArguments.arguments(for: .generationalZGC, javaMajorVersion: 20).contains("-XX:+UseG1GC"))
        #expect(GarbageCollectorArguments.arguments(for: .generationalZGC, javaMajorVersion: 21).contains("-XX:+UseZGC"))
    }

    @Test("调优 G1GC 比标准 G1GC 多出比例参数，且 Java 8 补 ParallelRefProcEnabled")
    func tunedG1AddsExtraArguments() {
        let standard: [String] = GarbageCollectorArguments.arguments(for: .g1, javaMajorVersion: 17)
        let tuned: [String] = GarbageCollectorArguments.arguments(for: .tunedG1, javaMajorVersion: 17)
        #expect(standard.contains("-XX:+UseG1GC"))
        #expect(!standard.contains("-XX:MinHeapFreeRatio=25"))
        #expect(tuned.contains("-XX:MinHeapFreeRatio=25"))
        #expect(tuned.contains("-XX:MaxHeapFreeRatio=40"))

        let tunedJava8: [String] = GarbageCollectorArguments.arguments(for: .tunedG1, javaMajorVersion: 8)
        #expect(tunedJava8.contains("-XX:+ParallelRefProcEnabled"))
        #expect(!tunedJava8.contains("-XX:MinHeapFreeRatio=25"))
    }

    @Test("接管前先从清单参数里剔除旧的 GC 开关与调参")
    func managedArgumentsAreStripped() {
        let manifest: [String] = [
            "-Djava.library.path=./natives",
            "-XX:+UseG1GC",
            "-XX:G1NewSizePercent=20",
            "-XX:MaxGCPauseMillis=50",
            "-Xmx2G"
        ]
        let filtered: [String] = GarbageCollectorArguments.removingManagedArguments(from: manifest)
        #expect(filtered == ["-Djava.library.path=./natives", "-Xmx2G"])
    }
}

struct MemoryAllocationTests {
    @Test("滑杆刻度单调递增，且首尾与 PCL2 一致")
    func sliderMappingIsMonotonic() {
        #expect(MemoryAllocation.gigabytes(forSliderPosition: 0) == 0.3)
        #expect(MemoryAllocation.gigabytes(forSliderPosition: MemoryAllocation.maximumSliderPosition) == 48)
        var previous: Double = 0
        for position in 0...MemoryAllocation.maximumSliderPosition {
            let value: Double = MemoryAllocation.gigabytes(forSliderPosition: position)
            #expect(value > previous)
            previous = value
        }
    }

    @Test("GB 反查刻度能回到原位置")
    func sliderRoundTrips() {
        for position in 0...MemoryAllocation.maximumSliderPosition {
            let gigabytes: Double = MemoryAllocation.gigabytes(forSliderPosition: position)
            #expect(MemoryAllocation.sliderPosition(forGigabytes: gigabytes) == position)
        }
    }

    @Test("自动配置的推荐值不低于保底值，且不把可用内存吃光")
    func automaticRecommendationIsBounded() {
        #expect(MemoryAllocation.recommendedGigabytes(availableGigabytes: 0) == 0.5)
        // 16 GB 可用时不该直接给到 16 GB。
        let plenty: Double = MemoryAllocation.recommendedGigabytes(availableGigabytes: 16)
        #expect(plenty > 2 && plenty < 8)
        // 装了 Mod 的版本应当拿到更多。
        let modded: Double = MemoryAllocation.recommendedGigabytes(availableGigabytes: 16, modCount: 300, modable: true)
        #expect(modded > plenty)
    }
}

