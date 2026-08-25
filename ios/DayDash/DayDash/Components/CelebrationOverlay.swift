import SwiftUI

/// A short, tasteful confetti burst + banner shown when the day's tasks hit 100%.
/// Non-interactive, auto-dismisses, and respects Reduce Motion (banner only).
struct CelebrationOverlay: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()
    @State private var bannerVisible = false

    private struct Particle {
        let x: Double        // 0...1 horizontal start
        let hue: Double
        let fallSpeed: Double
        let drift: Double
        let size: Double
        let delay: Double
        let spin: Double
    }

    @State private var particles: [Particle] = (0..<32).map { _ in
        Particle(
            x: .random(in: 0...1),
            hue: [0.02, 0.07, 0.11, 0.55, 0.83].randomElement() ?? 0.07,  // warm + a little contrast
            fallSpeed: .random(in: 0.28...0.55),
            drift: .random(in: -50...50),
            size: .random(in: 6...11),
            delay: .random(in: 0...0.35),
            spin: .random(in: -4...4)
        )
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(startDate)
                        for p in particles {
                            let pt = t - p.delay
                            guard pt > 0 else { continue }
                            let progress = pt * p.fallSpeed
                            guard progress < 1.25 else { continue }
                            let y = progress * (size.height + 60) - 30
                            let x = p.x * size.width + sin(progress * .pi * 2) * p.drift
                            var ctx = context
                            ctx.opacity = max(0, 1.25 - progress)
                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: .radians(pt * p.spin))
                            let rect = CGRect(x: -p.size / 2, y: -p.size * 0.8,
                                              width: p.size, height: p.size * 1.6)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                                     with: .color(Color(hue: p.hue, saturation: 0.55, brightness: 0.95)))
                        }
                    }
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 6) {
                Text("🎉")
                    .font(.system(size: 44))
                Text("Day complete!")
                    .font(Theme.rounded(.title3, weight: .bold))
                Text("Every task done. Go enjoy it.")
                    .font(Theme.rounded(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28).padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
            .scaleEffect(bannerVisible ? 1 : 0.8)
            .opacity(bannerVisible ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { bannerVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeOut(duration: 0.35)) { bannerVisible = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { onFinished() }
        }
    }
}
