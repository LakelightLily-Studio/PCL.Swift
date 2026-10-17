//
//  ByteFormatTests.swift
//  PCL.Mac.Tests
//

import Foundation
import Testing
import Core

/// `ByteFormat` 是纯逻辑，是"改错了也没人发现"的高危位置，所以单独覆盖。
struct ByteFormatTests {
    @Test func sizesBelowOneKilobyteAreShownAsBytes() {
        #expect(ByteFormat.string(0) == "0 B")
        #expect(ByteFormat.string(1023) == "1023 B")
    }

    @Test func unitsStepEvery1024() {
        #expect(ByteFormat.string(1024) == "1.0 KB")
        #expect(ByteFormat.string(1024 * 1024) == "1.0 MB")
        #expect(ByteFormat.string(1024 * 1024 * 1024) == "1.0 GB")
        #expect(ByteFormat.string(1024 * 1024 * 1024 * 1024) == "1.0 TB")
    }

    @Test func valueAtOrAboveTenDropsTheDecimal() {
        // 10 以下保留一位小数，10 及以上取整，避免面板宽度抖动。
        #expect(ByteFormat.string(9 * 1024) == "9.0 KB")
        #expect(ByteFormat.string(10 * 1024) == "10 KB")
    }

    @Test func unitIndexStopsAtTerabytes() {
        #expect(ByteFormat.string(1024 * 1024 * 1024 * 1024 * 1024) == "1024 TB")
    }

    @Test func perSecondSuffixIsAppliedToEveryUnit() {
        #expect(ByteFormat.string(512, perSecond: true) == "512 B/s")
        #expect(ByteFormat.string(1024, perSecond: true) == "1.0 KB/s")
        #expect(ByteFormat.string(1024 * 1024, perSecond: true) == "1.0 MB/s")
    }
}
