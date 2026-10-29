//
//  ConfettiView.swift
//  PCL.Swift
//
//  完成页的彩带动画：从左下角向上喷出彩色碎片与彩带。
//  用 Canvas + TimelineView 逐帧绘制，不依赖任何 macOS 13+ API。
//

import SwiftUI

struct ConfettiView: View {
    @State private var startDate: Date = .init()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let elapsed: TimeInterval = timeline.date.timeIntervalSince(startDate)
            if elapsed < Self.maxDuration {
                Canvas { context, size in
                    draw(at: elapsed, context: context, size: size)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - 粒子

    private static let maxDuration: TimeInterval = 6.0
    private static let particles: [Particle] = makeParticles()

    private struct Particle {
        let angle: Double
        let speed: Double
        let gravity: Double
        let originX: Double
        let originY: Double
        let initialRotation: Double
        let rotationSpeed: Double
        let size: CGSize
        let color: Color
        let kind: Kind
        let delay: Double
        let lifetime: Double
        let sway: Double
        let swayFrequency: Double
        let swayPhase: Double

        enum Kind {
            case fragment
            case ribbon
            case dot
        }
    }

    private static let palette: [Color] = [
        Color(0xFF6B6B),
        Color(0xFF8E44),
        Color(0xF4C430),
        Color(0x6BCB77),
        Color(0x4D96FF),
        Color(0x9B5DE5),
        Color(0xF15BB5),
        Color(0x00BBF9),
    ]

    private static func makeParticles() -> [Particle] {
        var rng: SeededGenerator = .init(seed: 0x5EED_2026)
        return (0..<120).map { _ in
            let kindRoll: Double = .random(in: 0.0..<1.0, using: &rng)
            let kind: Particle.Kind = kindRoll < 0.55 ? .fragment : (kindRoll < 0.85 ? .ribbon : .dot)
            let width: CGFloat = kind == .ribbon
                ? CGFloat.random(in: 6...10, using: &rng)
                : CGFloat.random(in: 4...9, using: &rng)
            let height: CGFloat = kind == .ribbon
                ? CGFloat.random(in: 14...26, using: &rng)
                : (kind == .dot ? width : CGFloat.random(in: 6...13, using: &rng))

            return Particle(
                angle: .random(in: -1.35 ... -0.55, using: &rng),
                speed: .random(in: 620 ... 1180, using: &rng),
                gravity: .random(in: 820 ... 1180, using: &rng),
                originX: .random(in: 0 ... 40, using: &rng),
                originY: .random(in: 0 ... 14, using: &rng),
                initialRotation: .random(in: 0 ... (2 * .pi), using: &rng),
                rotationSpeed: .random(in: -7 ... 7, using: &rng),
                size: CGSize(width: width, height: height),
                color: palette[Int.random(in: 0..<palette.count, using: &rng)],
                kind: kind,
                delay: .random(in: 0 ... 0.65, using: &rng),
                lifetime: .random(in: 3.0 ... 5.2, using: &rng),
                sway: .random(in: 0 ... 18, using: &rng),
                swayFrequency: .random(in: 2 ... 5, using: &rng),
                swayPhase: .random(in: 0 ... (2 * .pi), using: &rng)
            )
        }
    }

    private func draw(at time: TimeInterval, context: GraphicsContext, size: CGSize) {
        let origin: CGPoint = .init(x: 6, y: size.height + 10)

        for particle in Self.particles {
            let local: TimeInterval = time - particle.delay
            guard local >= 0, local <= particle.lifetime else { continue }

            let x: CGFloat = origin.x + CGFloat(
                particle.originX
                + particle.speed * cos(particle.angle) * local
                + particle.sway * sin(local * particle.swayFrequency + particle.swayPhase)
            )
            let y: CGFloat = origin.y + CGFloat(
                particle.originY
                + particle.speed * sin(particle.angle) * local
                + 0.5 * particle.gravity * local * local
            )
            guard y < size.height + 80 else { continue }

            let fadeIn: Double = min(1, local / 0.06)
            let fadeOut: Double = min(1, max(0, (particle.lifetime - local) / 0.45))

            var ctx: GraphicsContext = context
            ctx.opacity = fadeIn * fadeOut
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: .radians(particle.initialRotation + particle.rotationSpeed * local))

            switch particle.kind {
            case .fragment:
                ctx.fill(fragmentPath(size: particle.size), with: .color(particle.color))
            case .ribbon:
                ctx.fill(ribbonPath(size: particle.size), with: .color(particle.color))
            case .dot:
                ctx.fill(dotPath(size: particle.size), with: .color(particle.color))
            }
        }
    }

    private func fragmentPath(size: CGSize) -> Path {
        Path(
            roundedRect: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ),
            cornerRadius: 1
        )
    }

    private func dotPath(size: CGSize) -> Path {
        Path(
            ellipseIn: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }

    private func ribbonPath(size: CGSize) -> Path {
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        var path: Path = .init()
        path.move(to: CGPoint(x: -w / 2, y: -h / 2))
        path.addCurve(
            to: CGPoint(x: w / 2, y: -h / 2 + 3),
            control1: CGPoint(x: -w / 6, y: -h / 2 - 3),
            control2: CGPoint(x: w / 6, y: -h / 2 + 6)
        )
        path.addLine(to: CGPoint(x: w / 2, y: h / 2 + 3))
        path.addCurve(
            to: CGPoint(x: -w / 2, y: h / 2),
            control1: CGPoint(x: w / 6, y: h / 2 + 6),
            control2: CGPoint(x: -w / 6, y: h / 2 - 3)
        )
        path.closeSubpath()
        return path
    }
}

/// 固定种子的伪随机数生成器：粒子参数每次启动都一致，避免 body 每帧重算时抖动。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
