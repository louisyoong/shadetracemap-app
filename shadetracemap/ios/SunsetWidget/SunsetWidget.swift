//
//  SunsetWidget.swift
//  SunsetWidget
//
//  Home-screen widget: current time (rendered live by WidgetKit itself,
//  via Text(date, style: .time)) plus today's sunset, which the Flutter
//  app writes into this App Group's shared storage - see
//  lib/home_widget_service.dart and this folder's README.md for the
//  one-time Xcode setup this needs.
//

import SwiftUI
import WidgetKit

// Must match the App Group configured on both this extension's and the
// Runner app's "Signing & Capabilities" tab, and _iosAppGroupId in
// lib/home_widget_service.dart.
private let widgetGroupId = "group.com.shadetracemap.shadetracemap"

private let sunsetAccent = Color(red: 1.0, green: 0.72, blue: 0.30)

struct SunsetEntry: TimelineEntry {
  let date: Date
  let sunsetText: String
  let locationLabel: String
}

struct SunsetProvider: TimelineProvider {
  func placeholder(in context: Context) -> SunsetEntry {
    SunsetEntry(date: Date(), sunsetText: "19:42", locationLabel: "Loading…")
  }

  func getSnapshot(in context: Context, completion: @escaping (SunsetEntry) -> Void) {
    completion(currentEntry(isPreview: context.isPreview))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SunsetEntry>) -> Void) {
    let entry = currentEntry(isPreview: context.isPreview)
    // The sunset text itself only changes once a day, but re-reading it
    // periodically picks up a location change (or the app pushing a fresh
    // value) without needing the app to be open. WidgetKit doesn't let a
    // Widget refresh itself continuously - this is a reasonable cadence for
    // something that mostly matters within a few minutes either way.
    let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
    completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
  }

  private func currentEntry(isPreview: Bool) -> SunsetEntry {
    let data = UserDefaults(suiteName: widgetGroupId)
    let sunsetText = data?.string(forKey: "sunset_time")
    let locationLabel = data?.string(forKey: "location_label")
    return SunsetEntry(
      date: Date(),
      sunsetText: sunsetText ?? (isPreview ? "19:42" : "--:--"),
      locationLabel: locationLabel ?? (isPreview ? "Kuala Lumpur" : "Open the app")
    )
  }
}

struct SunsetWidgetEntryView: View {
  var entry: SunsetProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.date, style: .time)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .minimumScaleFactor(0.8)
        .lineLimit(1)

      Spacer(minLength: 4)

      HStack(spacing: 6) {
        Image(systemName: "sunset.fill")
          .font(.system(size: 14))
          .foregroundColor(sunsetAccent)
        Text(entry.sunsetText)
          .font(.system(size: 17, weight: .semibold, design: .rounded))
          .foregroundColor(.white)
      }

      Text(entry.locationLabel)
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.65))
        .lineLimit(1)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.09, green: 0.15, blue: 0.28),
          Color(red: 0.02, green: 0.03, blue: 0.07),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }
}

@main
struct SunsetWidget: Widget {
  let kind: String = "SunsetWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SunsetProvider()) { entry in
      SunsetWidgetEntryView(entry: entry)
        .containerBackground(.clear, for: .widgetBackground)
    }
    .configurationDisplayName("Sunset")
    .description("Current time and today's sunset.")
    .supportedFamilies([.systemSmall])
  }
}

struct SunsetWidget_Previews: PreviewProvider {
  static var previews: some View {
    SunsetWidgetEntryView(
      entry: SunsetEntry(date: Date(), sunsetText: "19:42", locationLabel: "Kuala Lumpur")
    )
    .previewContext(WidgetPreviewContext(family: .systemSmall))
  }
}
