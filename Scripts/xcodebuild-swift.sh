#!/bin/bash
#
# 用指定的 Swift 工具链构建 / 测试本项目。
#
# 为什么需要这个脚本：本机装了两套工具链——Xcode 自带的 Swift 6.0，以及
# /Library/Developer/Toolchains 下的 Swift 6.4。后者在 Xcode UI 里可以直接选，
# 但命令行下 TOOLCHAINS=... 与 -toolchain ... 都不生效：
#
#   TOOLCHAINS=swift-6.4.0-RELEASE          # 目录名不是合法标识符，被静默忽略
#   TOOLCHAINS=swift-latest                 # 软链名同样被忽略
#   xcodebuild -toolchain swift-6.4.0-RELEASE
#   TOOLCHAINS=org.swift.640202609131a      # 标识符对了，但 SPM 解析阶段
#                                           # 会因 -disallow-use-new-driver 崩掉
#
# 唯一稳定可靠的方式是覆盖 SWIFT_EXEC 指向 6.4 的 swiftc：xcodebuild 用它编译，
# 同时保留 Xcode 的 SDK 与 clang，SPM 依赖解析也照常工作。
#
# 用法：
#   Scripts/xcodebuild-swift.sh build  [Debug|Release]
#   Scripts/xcodebuild-swift.sh test
#   Scripts/xcodebuild-swift.sh build Debug /path/to/other.xctoolchain/usr/bin/swiftc
#
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION="${1:-build}"
CONFIGURATION="${2:-Debug}"
SWIFTC="${3:-}"

if [ -z "$SWIFTC" ]; then
    # 优先用 swift-latest 软链指向的工具链，其次退回 Xcode 默认。
    if [ -x /Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc
    else
        SWIFTC="$(xcrun --find swiftc)"
    fi
fi

echo "swiftc: $SWIFTC"
"$SWIFTC" --version | head -1

case "$ACTION" in
    build)
        exec xcodebuild build \
            -project PCL.Swift.xcodeproj \
            -scheme PCL.Swift \
            -configuration "$CONFIGURATION" \
            -destination 'platform=macOS' \
            SWIFT_EXEC="$SWIFTC"
        ;;
    test)
        exec xcodebuild test \
            -project PCL.Swift.xcodeproj \
            -scheme PCL.Swift \
            -destination 'platform=macOS' \
            SWIFT_EXEC="$SWIFTC"
        ;;
    *)
        echo "用法: $0 {build|test} [Debug|Release] [swiftc 路径]" >&2
        exit 64
        ;;
esac
