//
//  TodayViewModel.swift
//  triprr
//
//  Drives the "Today" screen: an at-a-glance view of what's happening now and
//  next on the trip in progress (Req 7). It picks the ACTIVE trip (one whose
//  range brackets `now`, evaluated in the trip's primary time zone), resolves
//  the active day within it, assembles that day's ordered `TimelineEntry` list,
//  and highlights the CURRENT and NEXT items — all evaluated against `now` in
//  the correct local zone (Req 7.1, 7.3).
//
//  `now` is injected so the selection and current/next computation are
//  deterministic in tests and previews.
//
//  Design choices (documented):
//  - ACTIVE trip: among the given trips, those with `.current` status
//    (start-of-first-day ≤ now ≤ end-of-last-day, in the trip's primary zone).
//    If several are in progress, the soonest-ending is chosen — the same tie
//    break the trip list uses for its "Current" group, so Today surfaces the
//    trip wrapping up next.
//  - ACTIVE day: the calendar day containing `now` in the active trip's primary
//    zone, snapped to the matching trip day.
//  - Timeline assembly is NOT duplicated: a `DayItineraryViewModel` for the
//    active trip builds the day's entries via its shared bucketing logic.
//  - CURRENT item: the entry whose `[start, end]` interval contains `now`; if
//    none is active, the most recent entry that has already started. Point-in-
//    time entries (no `end`) count as current only at their exact instant, so
//    "current" otherwise falls back to the most-recently-started item.
//  - NEXT item: the soonest entry whose `start` is strictly after `now`.
//  - NO active trip: if an upcoming trip exists, surface the soonest-starting
//    one with a countdown; otherwise an empty "no trip in progress" state.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class TodayViewModel {

    /// The overall state of the Today screen.
    enum State: Equatable {
        /// A trip is in progress; show its active day.
        case active(ActiveDay)
        /// No trip in progress, but one is coming up — show it with a countdown.
        case upcoming(UpcomingTrip)
        /// Nothing in progress and nothing upcoming.
        case noTrip
    }

    /// The resolved active trip/day and its highlighted items.
    struct ActiveDay: Equatable {
        /// The trip in progress.
        let trip: Trip
        /// The start-of-day instant for the active day, in the trip's primary zone.
        let dayStart: Date
        /// The active day's entries, in chronological order.
        let entries: [TimelineEntry]
        /// The item happening now (or the most recently started), if any.
        let current: TimelineEntry?
        /// The soonest upcoming item on the day, if any.
        let next: TimelineEntry?
        /// The time zone "now" is evaluated in (the trip's primary zone).
        let timeZone: TimeZone

        static func == (lhs: ActiveDay, rhs: ActiveDay) -> Bool {
            lhs.trip.id == rhs.trip.id
                && lhs.dayStart == rhs.dayStart
                && lhs.entries == rhs.entries
                && lhs.current == rhs.current
                && lhs.next == rhs.next
                && lhs.timeZone == rhs.timeZone
        }
    }

    /// The next upcoming trip surfaced when nothing is in progress.
    struct UpcomingTrip: Equatable {
        let trip: Trip
        let countdown: TripCountdown
        let timeZone: TimeZone

        static func == (lhs: UpcomingTrip, rhs: UpcomingTrip) -> Bool {
            lhs.trip.id == rhs.trip.id
                && lhs.countdown == rhs.countdown
                && lhs.timeZone == rhs.timeZone
        }
    }

    /// The instant "now" is evaluated against. Injected for determinism; the
    /// view refreshes it as time passes.
    var now: Date {
        didSet { recompute() }
    }

    /// All trips the screen chooses from (typically every saved trip). Setting
    /// this recomputes the state.
    var trips: [Trip] {
        didSet { recompute() }
    }

    /// The current resolved state.
    private(set) var state: State = .noTrip

    init(trips: [Trip] = [], now: Date = Date()) {
        self.trips = trips
        self.now = now
        recompute()
    }

    /// Updates the trip set and `now` together (one recompute). The view calls
    /// this on appear / when the fetched trips change.
    func update(trips: [Trip], now: Date) {
        self.trips = trips
        self.now = now // triggers recompute via didSet
    }

    /// Advances `now` to the current wall-clock instant, refreshing the screen.
    func refreshNow() {
        now = Date()
    }

    // MARK: - Convenience accessors

    /// The active day, if a trip is in progress.
    var activeDay: ActiveDay? {
        if case .active(let day) = state { return day }
        return nil
    }

    /// The upcoming trip, if that's the current state.
    var upcomingTrip: UpcomingTrip? {
        if case .upcoming(let up) = state { return up }
        return nil
    }

    /// Whether a trip is currently in progress.
    var hasActiveTrip: Bool { activeDay != nil }

    // MARK: - Resolution

    private func recompute() {
        if let day = Self.resolveActiveDay(from: trips, now: now) {
            state = .active(day)
        } else if let up = Self.resolveUpcoming(from: trips, now: now) {
            state = .upcoming(up)
        } else {
            state = .noTrip
        }
    }

    /// Picks the active trip (soonest-ending in-progress trip) and builds its
    /// active day with current/next highlighted.
    private static func resolveActiveDay(from trips: [Trip], now: Date) -> ActiveDay? {
        let inProgress = trips
            .filter { $0.status(now: now) == .current }
            .sorted { $0.endDate < $1.endDate }
        guard let trip = inProgress.first else { return nil }

        let zone = trip.primaryTimeZone

        // Reuse the shared day-assembly logic rather than duplicating bucketing.
        let dayVM = DayItineraryViewModel(trip: trip, now: now)
        let dayStart = dayVM.selectedDayStart
            ?? DateHelpers.startOfDay(for: now, in: zone)
        let entries = dayVM.entries(forDayStarting: dayStart)

        let current = currentEntry(in: entries, now: now)
        let next = nextEntry(in: entries, now: now)

        return ActiveDay(
            trip: trip,
            dayStart: dayStart,
            entries: entries,
            current: current,
            next: next,
            timeZone: zone
        )
    }

    /// Picks the soonest-starting upcoming trip, with its countdown.
    private static func resolveUpcoming(from trips: [Trip], now: Date) -> UpcomingTrip? {
        let upcoming = trips
            .filter { $0.status(now: now) == .upcoming }
            .sorted { $0.startDate < $1.startDate }
        guard let trip = upcoming.first else { return nil }
        let zone = trip.primaryTimeZone
        let countdown = TripCountdown.make(
            start: trip.startDate,
            end: trip.endDate,
            timeZone: zone,
            now: now
        )
        return UpcomingTrip(trip: trip, countdown: countdown, timeZone: zone)
    }

    // MARK: - Current / next (Req 7.1)

    /// The entry happening *now*: the one whose `[start, end]` interval contains
    /// `now`. When no entry is strictly active (e.g. between items, or the day's
    /// items are point-in-time), falls back to the most recent entry that has
    /// already started, so the screen still anchors on "where we are".
    static func currentEntry(in entries: [TimelineEntry], now: Date) -> TimelineEntry? {
        // Prefer an entry actively spanning `now`.
        let spanning = entries.filter { entry in
            let end = entry.end ?? entry.start
            return entry.start <= now && now <= end
        }
        // If several span now, prefer the one that started most recently.
        if let active = spanning.max(by: { $0.start < $1.start }) {
            return active
        }
        // Otherwise the most recent item that has already started.
        return entries
            .filter { $0.start <= now }
            .max(by: { $0.start < $1.start })
    }

    /// The soonest entry whose `start` is strictly after `now`.
    static func nextEntry(in entries: [TimelineEntry], now: Date) -> TimelineEntry? {
        entries
            .filter { $0.start > now }
            .min(by: { $0.start < $1.start })
    }
}
