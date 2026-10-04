//
//  DayItineraryViewModel.swift
//  triprr
//
//  Builds the ordered `TimelineEntry` list for a single day of a trip,
//  unifying flights, stays, bookings and activities (Req 4.1). Day bucketing is
//  done in the local time zone of the item involved via `DateHelpers`, so each
//  item lands on the right calendar day for the place it belongs to (Req 4.1,
//  3.3). Multi-night stays place check-in on the arrival day and check-out on
//  the departure day, with an "overnight" indicator on the nights in between,
//  rather than duplicating check-in/out on every day (Req 3.4).
//
//  Travel-time legs between consecutive placed entries are computed here and
//  estimated via the injected `RoutingService`, with results cached across day
//  switches and failures degrading gracefully (Req 4.4, 4.6). Schedule warnings
//  layer on top of the same ordered entries via the pure `ScheduleEvaluator`:
//  for each consecutive pair it classifies the gap as ok / tight / overlap
//  against a configurable buffer plus the resolved travel time, flagging a leg
//  that is too tight to reach the next item — including the extra lead time
//  before a flight (Req 4.5). The buffer is exposed on the VM so a future
//  setting can change it.
//

import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class DayItineraryViewModel {

    /// The travel leg between two consecutive placed entries on a day. The leg
    /// is "attached" to the entry it follows (`afterEntryID`) so the view can
    /// render it beneath that row.
    struct TravelLeg: Identifiable, Hashable {
        /// The entry this leg follows in the timeline.
        let afterEntryID: UUID
        let origin: Place
        let destination: Place
        let mode: TravelMode

        var id: UUID { afterEntryID }

        var routeLeg: RouteLeg {
            RouteLeg(origin: origin, destination: destination, mode: mode)
        }
    }

    /// The display state of a leg's estimate, surfaced to the view.
    enum LegState: Equatable {
        /// The estimate is being computed.
        case loading
        /// The estimate resolved successfully.
        case estimate(RouteEstimate)
        /// Directions couldn't be computed; the view degrades gracefully by
        /// showing a subtle "travel time unavailable" (Req 4.6).
        case unavailable
    }

    /// The trip whose days this view model lays out.
    let trip: Trip

    /// The currently selected day, represented by its start-of-day instant in
    /// the trip's primary time zone. `nil` until the first day is resolved.
    var selectedDayStart: Date?

    /// Resolved leg states keyed by `TravelLeg.id` (the preceding entry's id).
    /// Cached across day switches so returning to a day doesn't refetch
    /// (Req 4.4). Mutating this republishes to the view.
    private(set) var legStates: [UUID: LegState] = [:]

    /// The routing service used to estimate legs. Defaults to the mock so
    /// previews/tests work without injection; the view supplies the app's
    /// service from the environment. The VM depends only on the protocol
    /// (Req 4.4).
    private var routing: any RoutingService

    /// The schedule buffer used to classify gaps between consecutive items
    /// (Req 4.5). Exposed so a future setting can change the comfortable gap
    /// and the pre-flight lead time; defaults to 15 min gap + 90 min flight
    /// lead. Mutating it republishes the warnings to the view.
    var scheduleBuffer: ScheduleBuffer

    init(
        trip: Trip,
        now: Date = Date(),
        routing: any RoutingService = MockRoutingService(),
        scheduleBuffer: ScheduleBuffer = .default
    ) {
        self.trip = trip
        self.routing = routing
        self.scheduleBuffer = scheduleBuffer
        self.selectedDayStart = Self.defaultSelectedDay(for: trip, now: now)
    }

    /// Injects the routing service from the environment once the view appears,
    /// since the service container isn't available at `init`.
    func use(routing: any RoutingService) {
        self.routing = routing
    }

    // MARK: - Days

    /// The ordered day-start instants spanning the trip, in the trip's primary
    /// zone. Drives the day switcher.
    var dayStarts: [Date] {
        DateHelpers.dayStarts(
            from: trip.startDate,
            to: trip.endDate,
            in: trip.primaryTimeZone
        )
    }

    /// A short label for a day in the switcher, e.g. "Mon 15 Oct".
    func dayLabel(_ dayStart: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .day()
            .month(.abbreviated)
        style.timeZone = trip.primaryTimeZone
        return dayStart.formatted(style)
    }

    /// A one-based "Day N of M" label for the selected day, if it falls within
    /// the trip's day range.
    func dayNumberLabel(_ dayStart: Date) -> String? {
        let days = dayStarts
        guard let index = days.firstIndex(of: dayStart) else { return nil }
        return "Day \(index + 1) of \(days.count)"
    }

    /// Advances the selection by `offset` days, clamped to the trip range.
    func stepDay(by offset: Int) {
        let days = dayStarts
        guard let current = selectedDayStart,
              let index = days.firstIndex(of: current) else {
            selectedDayStart = days.first
            return
        }
        let target = index + offset
        guard days.indices.contains(target) else { return }
        selectedDayStart = days[target]
    }

    /// Whether the selection can move earlier/later (for disabling the arrows).
    var canStepBackward: Bool { stepAvailability(offset: -1) }
    var canStepForward: Bool { stepAvailability(offset: 1) }

    private func stepAvailability(offset: Int) -> Bool {
        let days = dayStarts
        guard let current = selectedDayStart,
              let index = days.firstIndex(of: current) else { return false }
        return days.indices.contains(index + offset)
    }

    // MARK: - Entries for the selected day

    /// The ordered timeline entries for the currently selected day, or an empty
    /// list if no day is selected.
    var entriesForSelectedDay: [TimelineEntry] {
        guard let day = selectedDayStart else { return [] }
        return entries(forDayStarting: day)
    }

    /// Whether the selected day has nothing scheduled.
    var selectedDayIsEmpty: Bool {
        entriesForSelectedDay.isEmpty
    }

    /// Assembles the chronological timeline for the calendar day beginning at
    /// `dayStart` (a start-of-day instant in the trip's primary zone).
    ///
    /// Each source item is bucketed using the local zone that matters for it
    /// (the item's own effective zone / airport zone), so an item is placed on
    /// the calendar day a traveller would actually experience it (Req 4.1,
    /// 3.3). The comparison uses the trip's primary zone as the common frame
    /// for the day boundary while respecting each item's instant.
    func entries(forDayStarting dayStart: Date) -> [TimelineEntry] {
        let zone = trip.primaryTimeZone
        var result: [TimelineEntry] = []

        // Flights — placed on the departure airport's local day (Req 2.3).
        for flight in trip.flights {
            if DateHelpers.isSameDay(flight.scheduledDeparture, dayStart, in: flight.departureTimeZone) {
                result.append(flight.timelineEntry)
            }
        }

        // Stays — multi-night placement (Req 3.4).
        for stay in trip.stays {
            result.append(contentsOf: stayEntries(for: stay, onDayStarting: dayStart))
        }

        // Bookings — placed on the booking's local day (Req 3.3).
        for booking in trip.bookings {
            if DateHelpers.isSameDay(booking.startDate, dayStart, in: booking.effectiveTimeZone) {
                result.append(booking.timelineEntry)
            }
        }

        // Activities — placed on the activity's local day (Req 4.1).
        for activity in trip.activities {
            if DateHelpers.isSameDay(activity.startDate, dayStart, in: activity.effectiveTimeZone) {
                result.append(activity.timelineEntry)
            }
        }

        _ = zone // reserved for future warning assembly seam (6.4)
        return result.chronological()
    }

    // MARK: - Placed entries for the map (Req 4.7)

    /// The selected day's timeline entries that have a `Place`, in itinerary
    /// (chronological) order. These are the stops the day map plots as a route
    /// and the stops the "Open in Apple Maps" button hands to Maps (Req 4.7).
    /// Entries without a place (e.g. a show with no venue set) are omitted so
    /// the route only connects locations we can actually point at.
    var placedEntriesForSelectedDay: [TimelineEntry] {
        entriesForSelectedDay.filter { $0.place != nil }
    }

    /// The ordered places for the selected day's placed entries — the route the
    /// map draws and Apple Maps opens, in time order (Req 4.7).
    var placedPlacesForSelectedDay: [Place] {
        placedEntriesForSelectedDay.compactMap(\.place)
    }

    /// Whether the selected day has at least two placed stops, i.e. enough to
    /// draw and open a multi-stop route (Req 4.7). With fewer than two the map
    /// still shows the single stop (or nothing) and the open-in-Maps action
    /// degrades gracefully.
    var selectedDayHasRoute: Bool {
        placedPlacesForSelectedDay.count >= 2
    }

    // MARK: - Travel legs (Req 4.4, 4.6)

    /// The default travel mode for legs when an activity doesn't override it.
    static let defaultTravelMode: TravelMode = .automobile

    /// The travel legs for the selected day: one for each pair of consecutive
    /// timeline entries that both have a `Place`. Entries without a place
    /// produce no leg, so the day view simply omits a travel estimate there
    /// (Req 4.6). The leg's mode comes from the destination activity's
    /// per-activity override when set, otherwise the default (Req 4.4).
    var travelLegsForSelectedDay: [TravelLeg] {
        travelLegs(for: entriesForSelectedDay)
    }

    /// Computes the travel legs between consecutive placed entries in `entries`.
    func travelLegs(for entries: [TimelineEntry]) -> [TravelLeg] {
        var legs: [TravelLeg] = []
        var previous: TimelineEntry?
        for entry in entries {
            defer { if entry.place != nil { previous = entry } }
            guard let from = previous?.place, let to = entry.place else { continue }
            // Skip a zero-length leg (same coordinate) — nothing to travel.
            if from.latitude == to.latitude && from.longitude == to.longitude { continue }
            legs.append(
                TravelLeg(
                    afterEntryID: previous!.id,
                    origin: from,
                    destination: to,
                    mode: travelMode(for: entry)
                )
            )
        }
        return legs
    }

    /// The travel mode to reach `entry`: the backing activity's override when
    /// present, otherwise the day's default.
    private func travelMode(for entry: TimelineEntry) -> TravelMode {
        if case .activity(let activityID) = entry.source,
           let activity = trip.activities.first(where: { $0.id == activityID }),
           let mode = activity.travelMode {
            return mode
        }
        return Self.defaultTravelMode
    }

    /// The resolved state for a leg, if one has been computed yet.
    func state(for leg: TravelLeg) -> LegState? {
        legStates[leg.id]
    }

    /// Fetches estimates for every leg on the selected day that hasn't been
    /// resolved yet, writing results into `legStates` as they arrive. Already
    /// resolved legs are skipped, so switching away and back to a day reuses
    /// the cached estimates and never refetches (Req 4.4). Routing failures
    /// (offline, no route, unavailable) resolve to `.unavailable` so the day
    /// view degrades gracefully rather than failing (Req 4.6).
    func loadTravelEstimates() async {
        let legs = travelLegsForSelectedDay
        for leg in legs {
            if legStates[leg.id] != nil { continue }
            legStates[leg.id] = .loading
            let routeLeg = leg.routeLeg
            do {
                let estimate = try await routing.estimate(routeLeg)
                legStates[leg.id] = .estimate(estimate)
            } catch {
                legStates[leg.id] = .unavailable
            }
        }
    }

    // MARK: - Schedule warnings (Req 4.5)

    /// The schedule gaps for the selected day: one verdict (ok / tight /
    /// overlap) per consecutive pair of timeline entries, computed by the pure
    /// `ScheduleEvaluator` from the ordered entries, the already-resolved travel
    /// estimates and the configurable buffer. A leg whose estimate is still
    /// loading or unavailable contributes no travel time (evaluated as 0), so a
    /// missing estimate never invents a warning — only a genuine overlap or a
    /// too-tight connection is flagged (Req 4.5, 4.6).
    var scheduleGapsForSelectedDay: [ScheduleGap] {
        scheduleGaps(for: entriesForSelectedDay)
    }

    /// Computes the schedule gaps for `entries` using the resolved travel
    /// estimates in `legStates`. Keyed to the preceding entry's id so each gap
    /// aligns with the travel leg (and row) it follows.
    func scheduleGaps(for entries: [TimelineEntry]) -> [ScheduleGap] {
        let items = entries.map {
            ScheduleItem(id: $0.id, start: $0.start, end: $0.end, isFlight: $0.isFlight)
        }
        return ScheduleEvaluator.evaluate(
            items: items,
            travelTimes: resolvedTravelTimes(for: entries),
            buffer: scheduleBuffer
        )
    }

    /// The resolved travel seconds for each leg on the day, keyed to the leg's
    /// preceding entry id. Legs still loading or unavailable are omitted, so the
    /// evaluator treats their travel time as unknown (0) rather than guessing.
    private func resolvedTravelTimes(for entries: [TimelineEntry]) -> [UUID: TimeInterval] {
        var times: [UUID: TimeInterval] = [:]
        for leg in travelLegs(for: entries) {
            if case .estimate(let estimate) = legStates[leg.id] {
                times[leg.afterEntryID] = estimate.travelTime
            }
        }
        return times
    }

    /// The schedule gap that follows `entry` on the selected day, if any — i.e.
    /// the verdict for the gap between `entry` and the next item. Returns `nil`
    /// for the last entry (no following gap).
    func scheduleGap(after entry: TimelineEntry) -> ScheduleGap? {
        scheduleGapsForSelectedDay.first { $0.afterEntryID == entry.id }
    }

    /// The warning (if any) to show *on* a row: a row carries the warning for
    /// the gap that precedes it, so "Tight connection" / "Overlaps previous"
    /// reads against the item the traveller is trying to reach. Returns `nil`
    /// when the preceding gap is comfortable or `entry` is the first item.
    func scheduleWarning(for entry: TimelineEntry) -> ScheduleGap? {
        guard let gap = scheduleGapsForSelectedDay.first(where: { $0.beforeEntryID == entry.id }),
              gap.isWarning else { return nil }
        return gap
    }

    /// The timeline entries a stay contributes to the day beginning at
    /// `dayStart`:
    /// - its check-in day: the check-in entry (plus an overnight indicator if
    ///   the stay continues past this day);
    /// - its check-out day: the check-out entry;
    /// - an intervening night: a single "Overnight at …" entry, so the stay is
    ///   represented without repeating check-in/out.
    private func stayEntries(for stay: Stay, onDayStarting dayStart: Date) -> [TimelineEntry] {
        let zone = stay.effectiveTimeZone
        let isCheckInDay = DateHelpers.isSameDay(stay.checkIn, dayStart, in: zone)
        let isCheckOutDay = DateHelpers.isSameDay(stay.checkOut, dayStart, in: zone)

        // A single-day stay (check in and out same calendar day): just show both.
        if isCheckInDay && isCheckOutDay {
            return [stay.checkInEntry, stay.checkOutEntry]
        }
        if isCheckInDay {
            return [stay.checkInEntry]
        }
        if isCheckOutDay {
            return [stay.checkOutEntry]
        }

        // Otherwise, is this day strictly between check-in and check-out? If so
        // the traveller is staying overnight — show an unobtrusive indicator
        // instead of nothing.
        let checkInDay = DateHelpers.startOfDay(for: stay.checkIn, in: zone)
        let checkOutDay = DateHelpers.startOfDay(for: stay.checkOut, in: zone)
        let thisDay = DateHelpers.startOfDay(for: dayStart, in: zone)
        if thisDay > checkInDay && thisDay < checkOutDay {
            return [overnightEntry(for: stay, onDayStarting: thisDay)]
        }
        return []
    }

    /// A lightweight "ongoing stay" entry anchored at the start of an
    /// intervening day, so a multi-night stay reads as present on that day
    /// without duplicating check-in/out.
    private func overnightEntry(for stay: Stay, onDayStarting dayStart: Date) -> TimelineEntry {
        TimelineEntry(
            id: deterministicOvernightID(stayID: stay.id, dayStart: dayStart),
            source: .stayCheckIn(stayID: stay.id),
            title: "Staying at \(stay.name)",
            subtitle: stay.place?.name,
            start: dayStart,
            end: nil,
            timeZoneIdentifier: stay.effectiveTimeZone.identifier,
            place: stay.place,
            symbolName: stay.kind.symbolName,
            // Sort ahead of same-instant activities so the ongoing stay reads
            // as the day's lodging context, but after flights/check-ins.
            sortOrder: -45,
            isDone: false
        )
    }

    /// A stable id for an overnight entry, derived from the stay id and the day
    /// it falls on, so SwiftUI diffing is stable across redraws without
    /// colliding with the stay's check-in/out entry ids.
    private func deterministicOvernightID(stayID: UUID, dayStart: Date) -> UUID {
        var hasher = Hasher()
        hasher.combine(stayID)
        hasher.combine(dayStart)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))

        var bytes = stayID.uuid
        withUnsafeBytes(of: hash) { raw in
            bytes.8 = raw[0]
            bytes.9 = raw[1]
            bytes.10 = raw[2]
            bytes.11 = raw[3]
            bytes.12 = raw[4]
            bytes.13 = raw[5]
            bytes.14 = raw[6]
            bytes.15 = raw[7]
        }
        return UUID(uuid: bytes)
    }

    // MARK: - Activity editing (add / edit / reorder / remove)

    /// The default start instant for a new activity created on the selected
    /// day: the start of that day shifted to a sensible hour (09:00) in the
    /// trip's primary zone, so the editor opens on the right day. Falls back to
    /// "now" when no day is selected.
    var defaultStartForNewActivity: Date? {
        guard let day = selectedDayStart else { return nil }
        let zone = trip.primaryTimeZone
        let cal = DateHelpers.calendar(in: zone)
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    /// Resolves the `Activity` backing a timeline entry, or nil for entries that
    /// originate from flights/stays/bookings (which are not editable here).
    func activity(for entry: TimelineEntry) -> Activity? {
        guard case .activity(let activityID) = entry.source else { return nil }
        return trip.activities.first { $0.id == activityID }
    }

    /// Whether a timeline entry represents an editable/reorderable activity.
    func isActivity(_ entry: TimelineEntry) -> Bool {
        if case .activity = entry.source { return true }
        return false
    }

    /// The activities on the selected day, in the same order they appear in the
    /// timeline. Used to drive reordering.
    func activitiesForSelectedDay() -> [Activity] {
        entriesForSelectedDay.compactMap(activity(for:))
    }

    /// Deletes the activity backing `entry`, if any, persisting immediately
    /// (Req 4.3). No-op for non-activity entries.
    func deleteActivity(for entry: TimelineEntry, in context: ModelContext) {
        guard let activity = activity(for: entry) else { return }
        context.delete(activity)
        try? context.save()
    }

    /// Reorders the selected day's activities by moving the items at `offsets`
    /// to `destination`, then rewrites their `sortOrder` so the new order
    /// survives a fresh fetch via `chronological()`'s sortOrder tiebreak
    /// (Req 4.3). Only the day's activities are affected; other entry types keep
    /// their place.
    func moveActivities(fromOffsets offsets: IndexSet, toOffset destination: Int, in context: ModelContext) {
        var ordered = activitiesForSelectedDay()
        guard !ordered.isEmpty else { return }
        ordered.move(fromOffsets: offsets, toOffset: destination)
        persistOrder(of: ordered, in: context)
    }

    /// Assigns a strictly increasing `sortOrder` to the given activities so the
    /// timeline's sortOrder tiebreak reflects the user's chosen order. The
    /// activities on a day typically share nearby start times; rewriting the
    /// full set keeps the ordering unambiguous.
    private func persistOrder(of activities: [Activity], in context: ModelContext) {
        // Base off the lowest existing sortOrder among the moved set so we don't
        // collide with activities on other days that share the sequence.
        let base = activities.map(\.sortOrder).min() ?? 0
        for (index, activity) in activities.enumerated() {
            activity.sortOrder = base + index
        }
        try? context.save()
    }

    // MARK: - Default day selection

    /// The day to show first: today if the trip is in progress, otherwise the
    /// trip's first day.
    private static func defaultSelectedDay(for trip: Trip, now: Date) -> Date? {
        let zone = trip.primaryTimeZone
        let days = DateHelpers.dayStarts(from: trip.startDate, to: trip.endDate, in: zone)
        guard !days.isEmpty else { return nil }
        let today = DateHelpers.startOfDay(for: now, in: zone)
        if let match = days.first(where: { DateHelpers.isSameDay($0, today, in: zone) }) {
            return match
        }
        return days.first
    }
}
