import SwiftUI

/// A circular progress ring with a glowing gradient track and an animated count.
/// The dashboard's "how's today going" glance.
struct ProgressRing: View {
    var progress: Double          // 0...1
    var lineWidth: CGFloat = 13
    var label: String
    var caption: String

    private var clamped: Double { max(0.0001, min(progress, 1)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Theme.amber, Theme.peach, Theme.terracotta, Theme.amber]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.peach.opacity(0.5), radius: 6)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: clamped)

            VStack(spacing: 1) {
                Text(label)
                    .font(Theme.rounded(.title3, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(Theme.rounded(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }
}
