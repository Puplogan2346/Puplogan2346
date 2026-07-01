import WidgetKit
import SwiftUI

// Palette (kept local so the widget target is self-contained).
private let peach = Color(red: 0.95, green: 0.65, blue: 0.49)
private let terracotta = Color(red: 0.71, green: 0.34, blue: 0.29)

// MARK: - Timeline

struct DayWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct DayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayWidgetEntry {
        DayWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayWidgetEntry) -> Void) {
        completion(DayWidgetEntry(date: Date(), snapshot: SharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayWidgetEntry>) -> Void) {
        let entry = DayWidgetEntry(date: Date(), snapshot: SharedStore.read())
        // The app reloads timelines whenever data changes; this hourly refresh is a fallback.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayWidget", provider: DayWidgetProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [peach.opacity(0.9), terracotta],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Today")
        .description("Your focus and progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct DayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.greeting)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Text(entry.snapshot.focusTitle ?? "Pick your one thing")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "checklist").imageScale(.small)
                Text("\(entry.snapshot.doneTasks)/\(entry.snapshot.totalTasks) done")
                    .font(.system(.caption, design: .rounded).weight(.medium))
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.snapshot.greeting)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Focus")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .textCase(.uppercase)
                Text(entry.snapshot.focusTitle ?? "Pick your one thing")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").imageScale(.small)
                    Text("\(entry.snapshot.habitsDone)/\(entry.snapshot.habitsTotal) habits")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MiniRing(progress: entry.snapshot.progress,
                     label: "\(entry.snapshot.doneTasks)/\(entry.snapshot.totalTasks)")
                .frame(width: 84, height: 84)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MiniRing: View {
    var progress: Double
    var label: String

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.0001, min(progress, 1)))
                .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text("tasks")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
