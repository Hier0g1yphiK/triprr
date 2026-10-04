//
//  TodayView.swift
//  triprr
//
//  The "Today" screen: at a glance, what's happening now and next on the trip
//  in progress (Req 7). When a trip is active it shows the trip/day header, the
//  CURRENT item (a "Now" badge) and the NEXT item (a "Next" badge) prominently,
//  then the rest of the day in time order — all in the day's local time zone
//  (Req 7.1, 7.3). When no trip is in progress it shows a sensible state: the
//  next upcoming trip with a countdown, or an empty "no trip in progress"
//  message (Req 7.2).
//
//  Trips are fetched with SwiftData `@Query`; the view model resolves the
//  active trip/day and current/next from an injected `now`, kept fresh while
//  the screen is visible. Shared across iPhone and Mac.
//

import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]

    @State private var viewModel = TodayViewModel()

    /// Refreshes `now` roughly every minute so "current/next" stays accurate
    /// while the screen is open.
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        content
            .navigationTitle("Today")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .onAppear { viewModel.update(trips: trips, now: Date()) }
            .onChange(of: trips) { _, newTrips in
                viewModel.update(trips: newTrips, now: Date())
            }
            .onReceive(ticker) { _ in viewModel.refreshNow() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .active(let day):
            ActiveTodayView(day: day)
        case .upcoming(let up):
            UpcomingTodayView(upcoming: up)
        case .noTrip:
            noTripState
        }
    }

    // MARK: - No trip (Req 7.2)

    private var noTripState: some View {
        ContentUnavailableView {
            Label("No trip in progress", systemImage: "sun.max")
        } description: {
            Text("When a trip is underway, today's plan — what's happening now and next — shows up here.")
        }
    }
}

// MARK: - Active day

/// The in-progress trip's active day: a header, the Now/Next highlight cards,
/// and the rest of the day in time order (Req 7.1).
private struct ActiveTodayView: View {
    let day: TodayViewModel.ActiveDay

    /// The entries that are neither the current nor the next item, so the
    /// "rest of day" list doesn't repeat the highlighted cards.
    private var remainingEntries: [TimelineEntry] {
        let highlighted = Set([day.current?.id, day.next?.id].compactMap { $0 })
        return day.entries.filter { !highlighted.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if day.current == nil && day.next == nil {
                    emptyDayState
                } else {
                    if let current = day.current {
                        TodayHighlightCard(entry: current, kind: .now)
                    }
                    if let next = day.next {
                        TodayHighlightCard(entry: next, kind: .next)
                    }
                }

                if !remainingEntries.isEmpty {
                    restOfDay
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.trip.name.isEmpty ? "Trip" : day.trip.name)
                .font(.title2.weight(.bold))
            Text(dayLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var dayLabel: String {
        var style = Date.FormatStyle.dateTime
            .weekday(.wide)
            .day()
            .month(.wide)
        style.timeZone = day.timeZone
        let date = day.dayStart.formatted(style)
        let zone = DateHelpers.zoneAbbreviation(day.dayStart, in: day.timeZone)
        return "\(date) · \(zone)"
    }

    private var restOfDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rest of day")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(remainingEntries) { entry in
                    TodayEntryRow(entry: entry)
                    if entry.id != remainingEntries.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var emptyDayState: some View {
        ContentUnavailableView {
            Label("Nothing scheduled today", systemImage: "calendar.day.timeline.left")
        } description: {
            Text("There's nothing planned for today on this trip. Add activities from the itinerary.")
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Upcoming trip (Req 7.2)

/// Shown when no trip is in progress but one is coming up: the trip and a
/// countdown to its start.
private struct UpcomingTodayView: View {
    let upcoming: TodayViewModel.UpcomingTrip

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(upcoming.trip.name.isEmpty ? "Trip" : upcoming.trip.name)
                        .font(.title2.weight(.bold))
                }

                HStack(spacing: 12) {
                    Image(systemName: "airplane.departure")
                        .font(.title)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(upcoming.countdown.label)
                            .font(.title3.weight(.semibold))
                        Text(DateHelpers.dateRangeString(
                            upcoming.trip.startDate,
                            upcoming.trip.endDate,
                            in: upcoming.timeZone
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next trip, \(upcoming.trip.name), \(upcoming.countdown.label)")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Highlight card (Now / Next)

/// A prominent card for the current or next item, with a colour-coded "Now" or
/// "Next" badge that is both visually and accessibly distinct (Req 7.1).
struct TodayHighlightCard: View {
    enum Kind {
        case now
        case next

        var badgeText: String { self == .now ? "Now" : "Next" }
        var tint: Color { self == .now ? .green : .accentColor }
        var accessibilityPrefix: String { self == .now ? "Happening now" : "Up next" }
    }

    let entry: TimelineEntry
    let kind: Kind

    private var timeLabel: String {
        if let end = entry.end {
            let start = DateHelpers.timeString(entry.start, in: entry.timeZone)
            let endTime = DateHelpers.timeString(end, in: entry.timeZone)
            return "\(start) – \(endTime)"
        }
        return DateHelpers.timeString(entry.start, in: entry.timeZone)
    }

    private var zoneLabel: String {
        DateHelpers.zoneAbbreviation(entry.start, in: entry.timeZone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                badge
                Spacer(minLength: 0)
                Text("\(timeLabel) \(zoneLabel)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.symbolName)
                    .font(.title2)
                    .foregroundStyle(kind.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.title3.weight(.semibold))
                        .strikethrough(entry.isDone, color: .secondary)
                    if let subtitle = entry.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var badge: some View {
        Text(kind.badgeText.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(kind.tint, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        var parts = ["\(kind.accessibilityPrefix): \(entry.title)"]
        parts.append(DateHelpers.timeStringWithZone(entry.start, in: entry.timeZone))
        if let subtitle = entry.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if entry.isDone { parts.append("done") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Plain row (rest of day)

/// A compact row for the rest of the day's items, mirroring the itinerary row's
/// time-in-zone layout but without the travel legs/warnings.
struct TodayEntryRow: View {
    let entry: TimelineEntry

    /// The time column's width, scaled with Dynamic Type so a time range plus
    /// zone label stays legible at accessibility sizes (matches the itinerary
    /// row).
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth = TimelineRowMetrics.timeColumnBaseWidth

    private var timeLabel: String {
        if let end = entry.end {
            let start = DateHelpers.timeString(entry.start, in: entry.timeZone)
            let endTime = DateHelpers.timeString(end, in: entry.timeZone)
            return "\(start) – \(endTime)"
        }
        return DateHelpers.timeString(entry.start, in: entry.timeZone)
    }

    private var zoneLabel: String {
        DateHelpers.zoneAbbreviation(entry.start, in: entry.timeZone)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                Text(zoneLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: timeColumnWidth, alignment: .trailing)

            Image(systemName: entry.symbolName)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .strikethrough(entry.isDone, color: .secondary)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if entry.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts = ["\(entry.title), \(DateHelpers.timeStringWithZone(entry.start, in: entry.timeZone))"]
        if let subtitle = entry.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if entry.isDone { parts.append("done") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Today — Active (Light)") {
    NavigationStack { TodayView() }
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Today — Active (Dark)") {
    NavigationStack { TodayView() }
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Today — Active (Large Type)") {
    NavigationStack { TodayView() }
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Today — No Trip In Progress") {
    NavigationStack { TodayView() }
        .modelContainer(SampleData.emptyContainer())
        .environment(\.appServices, .mock)
}
