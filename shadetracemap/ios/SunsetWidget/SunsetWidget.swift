//
//  SunsetWidget.swift
//  SunsetWidget
//
//  Home-screen widget: a live countdown to whichever sun event is actually
//  next - sunrise before dawn, sunset during the day, or tomorrow's
//  sunrise once tonight's sun has already set - plotted on a rising "sun
//  arc" graphic (styled after golden-hour widgets like Sun Seeker /
//  Golden Hour), sourced from instants the Flutter app writes into this
//  App Group's shared storage - see lib/home_widget_service.dart and this
//  folder's README.md for the one-time Xcode setup this needs. The
//  countdown and the small size's clock are both rendered by SwiftUI's own
//  self-updating Text views, so neither needs a per-second (or even
//  per-minute) timeline reload to stay current.
//

import SwiftUI
import WidgetKit

// Must match the App Group configured on both this extension's and the
// Runner app's "Signing & Capabilities" tab, and _iosAppGroupId in
// lib/home_widget_service.dart.
private let widgetGroupId = "group.com.shadetracemap.shadetracemap"

// A single warm gold used throughout (title, arc, sun marker) rather than a
// second cool accent for sunset - the reference look this widget is styled
// after is entirely warm/dark, no blue - for both the sunrise and sunset
// countdowns.
private let sunGold = Color(red: 1.0, green: 0.72, blue: 0.30)

struct SunsetEntry: TimelineEntry {
  let date: Date
  /// Yesterday's sunset, today's sunrise/sunset, and tomorrow's sunrise -
  /// see [SunPhaseInfo] for why all four are needed rather than just
  /// today's pair.
  let prevSunsetDate: Date?
  let sunriseDate: Date?
  let sunsetDate: Date?
  let nextSunriseDate: Date?
  let locationLabel: String
}

struct SunsetProvider: TimelineProvider {
  func placeholder(in context: Context) -> SunsetEntry {
    SunsetEntry(
      date: Date(),
      prevSunsetDate: Calendar.current.date(byAdding: .hour, value: -18, to: Date()),
      sunriseDate: Calendar.current.date(byAdding: .hour, value: -6, to: Date()),
      sunsetDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
      nextSunriseDate: Calendar.current.date(byAdding: .hour, value: 18, to: Date()),
      locationLabel: "Loading…"
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (SunsetEntry) -> Void) {
    completion(currentEntry(isPreview: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SunsetEntry>) -> Void) {
    let entry = currentEntry(isPreview: context.isPreview)
    // These instants only change once a day, but re-reading periodically
    // picks up a location change (or a fresh value the app pushed) without
    // needing the app to be open. WidgetKit doesn't let a Widget refresh
    // itself continuously - this is a reasonable cadence for something
    // that mostly matters within a few minutes either way. It's also what
    // picks up the sunrise/sunset/night boundary crossings themselves
    // (the phase in [SunPhaseInfo] is derived fresh every time this runs).
    // The live clock and countdown stay current between reloads on their
    // own via SwiftUI's Text(date:style:) / Text(timerInterval:).
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }

  private func currentEntry(isPreview: Bool) -> SunsetEntry {
    let data = UserDefaults(suiteName: widgetGroupId)

    func date(forKey key: String) -> Date? {
      guard let raw = data?.string(forKey: key), let ms = Double(raw) else { return nil }
      return Date(timeIntervalSince1970: ms / 1000)
    }

    var prevSunsetDate = date(forKey: "prev_sunset_epoch_ms")
    var sunriseDate = date(forKey: "sunrise_epoch_ms")
    var sunsetDate = date(forKey: "sunset_epoch_ms")
    var nextSunriseDate = date(forKey: "next_sunrise_epoch_ms")
    let locationLabel = data?.string(forKey: "location_label")

    // The gallery calls getSnapshot(isPreview: true) before the app has
    // ever run and written real data - show plausible sample times there
    // instead of "--:--", same idea as the example app's own placeholder.
    if isPreview && sunriseDate == nil && sunsetDate == nil {
      prevSunsetDate = Calendar.current.date(byAdding: .hour, value: -18, to: Date())
      sunriseDate = Calendar.current.date(byAdding: .hour, value: -6, to: Date())
      sunsetDate = Calendar.current.date(byAdding: .minute, value: 37, to: Date())
      nextSunriseDate = Calendar.current.date(byAdding: .hour, value: 18, to: Date())
    }

    return SunsetEntry(
      date: Date(),
      prevSunsetDate: prevSunsetDate,
      sunriseDate: sunriseDate,
      sunsetDate: sunsetDate,
      nextSunriseDate: nextSunriseDate,
      locationLabel: locationLabel ?? (isPreview ? "Kuala Lumpur" : "Open the app")
    )
  }
}

private let timeFormatter: DateFormatter = {
  let f = DateFormatter()
  f.timeStyle = .short
  return f
}()

/// Which sun event is actually next right now, and everything the views
/// need to render it: a title/icon, what to count down to, a 0...1
/// progress fraction through the current window (night or day) for
/// [SunArcGraphic]'s marker, and the window's start/end for the range
/// label. Computed fresh from an [SunsetEntry] rather than stored on it,
/// since it depends on "now" (`entry.date`), not just the four instants.
private struct SunPhaseInfo {
  let title: String
  let icon: String
  let targetDate: Date?
  let progress: Double
  let rangeStart: Date?
  let rangeEnd: Date?

  init(entry: SunsetEntry) {
    let now = entry.date

    func progressBetween(_ start: Date?, _ end: Date?) -> Double {
      guard let start, let end, end > start else { return 0.5 }
      let total = end.timeIntervalSince(start)
      let elapsed = now.timeIntervalSince(start)
      return min(max(elapsed / total, 0), 1)
    }

    if let sunrise = entry.sunriseDate, now < sunrise {
      // Before dawn: counting down to today's sunrise, "tonight" running
      // from yesterday's sunset to it.
      title = "Sunrise"
      icon = "sunrise.fill"
      targetDate = sunrise
      progress = progressBetween(entry.prevSunsetDate, sunrise)
      rangeStart = entry.prevSunsetDate
      rangeEnd = sunrise
    } else if let sunrise = entry.sunriseDate, let sunset = entry.sunsetDate, now < sunset {
      // Daytime: counting down to today's sunset.
      title = "Sunset"
      icon = "sunset.fill"
      targetDate = sunset
      progress = progressBetween(sunrise, sunset)
      rangeStart = sunrise
      rangeEnd = sunset
    } else {
      // The sun's already set today (or we don't know today's sunrise at
      // all): counting down to *tomorrow's* sunrise instead of showing a
      // stale "sunset" that already happened.
      title = "Sunrise"
      icon = "sunrise.fill"
      targetDate = entry.nextSunriseDate
      progress = progressBetween(entry.sunsetDate, entry.nextSunriseDate)
      rangeStart = entry.sunsetDate
      rangeEnd = entry.nextSunriseDate
    }
  }
}

struct SunsetWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  var entry: SunsetProvider.Entry

  var body: some View {
    switch family {
    case .systemMedium:
      MediumSunsetView(entry: entry)
    default:
      SmallSunsetView(entry: entry)
    }
  }
}

/// Compact size: clock, a small sun-arc graphic, and whichever event
/// ([SunPhaseInfo]) is next.
struct SmallSunsetView: View {
  var entry: SunsetProvider.Entry

  var body: some View {
    let phase = SunPhaseInfo(entry: entry)

    ZStack(alignment: .topLeading) {
      SunArcGraphic(progress: phase.progress)
        .opacity(0.9)

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.date, style: .time)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundColor(.white)
          .minimumScaleFactor(0.8)
          .lineLimit(1)

        Spacer(minLength: 4)

        HStack(spacing: 6) {
          Image(systemName: phase.icon)
            .font(.system(size: 13))
            .foregroundColor(sunGold)
          Text(phase.targetDate.map { timeFormatter.string(from: $0) } ?? "--:--")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
        }

        HStack(spacing: 4) {
          Image(systemName: "location.fill")
            .font(.system(size: 9))
          Text(entry.locationLabel)
            .font(.system(size: 11))
            .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.6))
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(backgroundGradient)
  }
}

/// Wide size: title + live countdown + the current window's range +
/// location on the left, the sun-arc graphic filling the right - all
/// driven by whichever event ([SunPhaseInfo]) is next.
struct MediumSunsetView: View {
  var entry: SunsetProvider.Entry

  var body: some View {
    let phase = SunPhaseInfo(entry: entry)

    HStack(alignment: .top, spacing: 4) {
      VStack(alignment: .leading, spacing: 5) {
        Text(phase.title)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundColor(sunGold)

        if let target = phase.targetDate, target > entry.date {
          Text(timerInterval: entry.date...target, countsDown: true)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .monospacedDigit()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
        } else {
          Text("--:--")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
        }

        Text(rangeText(phase))
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundColor(.white.opacity(0.6))

        Spacer(minLength: 6)

        HStack(spacing: 4) {
          Image(systemName: "location.fill")
            .font(.system(size: 10))
          Text(entry.locationLabel)
            .font(.system(size: 12))
            .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.6))
      }
      .frame(maxHeight: .infinity, alignment: .topLeading)

      SunArcGraphic(progress: phase.progress)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(backgroundGradient)
  }

  private func rangeText(_ phase: SunPhaseInfo) -> String {
    guard let start = phase.rangeStart, let end = phase.rangeEnd else {
      return "--:-- – --:--"
    }
    return "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
  }
}

/// A rising curve from bottom-leading to top-trailing, golden near "now"
/// and fading to the dark background color further along, with a small
/// glowing sun marker at [progress] (0...1) along that same curve. Purely
/// decorative - it doesn't plot a real azimuth/altitude path, just gives
/// the countdown a sense of "how far into this stretch of day or night"
/// the current moment sits.
private struct SunArcGraphic: View {
  let progress: Double

  var body: some View {
    GeometryReader { geo in
      let rect = CGRect(origin: .zero, size: geo.size)
      let start = CGPoint(x: rect.minX + rect.width * 0.10, y: rect.maxY - rect.height * 0.12)
      let end = CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.10)
      let control = CGPoint(x: rect.minX + rect.width * 0.68, y: rect.maxY - rect.height * 0.04)

      ZStack {
        Path { path in
          path.move(to: start)
          path.addQuadCurve(to: end, control: control)
        }
        .stroke(
          LinearGradient(
            colors: [sunGold, sunGold.opacity(0.9), Color.black.opacity(0.05)],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
          ),
          style: StrokeStyle(lineWidth: 5, lineCap: .round)
        )

        let marker = quadPoint(start: start, control: control, end: end, t: CGFloat(progress))
        ZStack {
          Circle()
            .fill(sunGold.opacity(0.35))
            .frame(width: 26, height: 26)
            .blur(radius: 3)
          Circle()
            .fill(Color.black.opacity(0.85))
            .frame(width: 17, height: 17)
          Circle()
            .fill(sunGold)
            .frame(width: 12, height: 12)
        }
        .position(marker)
      }
    }
  }
}

/// Point at parameter `t` (0...1) along the same quadratic bezier
/// [SunArcGraphic] strokes, so the sun marker always sits exactly on the
/// visible curve instead of needing to be eyeballed into place separately.
private func quadPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
  let mt = 1 - t
  let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
  let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
  return CGPoint(x: x, y: y)
}

private let backgroundGradient = LinearGradient(
  colors: [
    Color(red: 0.09, green: 0.15, blue: 0.28),
    Color(red: 0.02, green: 0.03, blue: 0.07),
  ],
  startPoint: .top,
  endPoint: .bottom
)

@main
struct SunsetWidget: Widget {
  let kind: String = "SunsetWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SunsetProvider()) { entry in
      SunsetWidgetEntryView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Sunset")
    .description("A live countdown to sunrise or sunset on a sun-arc graphic.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct SunsetWidget_Previews: PreviewProvider {
  static var previews: some View {
    let entry = SunsetEntry(
      date: Date(),
      prevSunsetDate: Calendar.current.date(byAdding: .hour, value: -18, to: Date()),
      sunriseDate: Calendar.current.date(byAdding: .hour, value: -6, to: Date()),
      sunsetDate: Calendar.current.date(byAdding: .minute, value: 37, to: Date()),
      nextSunriseDate: Calendar.current.date(byAdding: .hour, value: 18, to: Date()),
      locationLabel: "Kuala Lumpur"
    )
    Group {
      SunsetWidgetEntryView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemSmall))
      SunsetWidgetEntryView(entry: entry)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
  }
}
