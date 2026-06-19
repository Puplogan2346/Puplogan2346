import SwiftUI

/// A circular progress ring with a label in the middle — the dashboard's "how's today going" glance.
struct ProgressRing: View {
    var progress: Double          // 0...1
    var lineWidth: CGFloat = 12
    var label: String
    var caption: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: [.accentColor, .accentColor.opacity(0.6)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: progress)
            VStack(spacing: 2) {
                Text(label).font(.title2.bold()).monospacedDigit()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
