//
//  ScheduleEvaluator.swift
//  triprr
//
//  A pure, dependency-free evaluator for day-schedule tightness (Req 4.5). It
//  decides, for each consecutive pair of timeline items on a day, whether the
//  gap between them is comfortable, tight, or an outright overlap once the
//  travel time between their places and a configurable buffer are taken into
//  account.
//
//  It touches no frameworks — no SwiftData, no MapKit, no SwiftUI — only value
//  types in and out, so it is fully unit-testable and reusable from the view
//  model. The caller (DayItineraryViewModel) feeds it lightweight value inputs
//  derived from `TimelineEntry` plus the per-leg travel estimates it already
//  resolved via `RoutingService`.
//

import Foundation

// MARK: - Buffer

/// The slack a traveller wants around consecutive items, plus the extra lead
/// time required before a flight. Configurable so a future setting can change
/// it; a sensible default is provided (Req 4.5, terminology "Buffer").
nonisolated struct ScheduleBuffer: Hashable, Sendable {
    /// The minimum comfortable gap (seconds) between the end of one item and
    /// the start of the next, on top of the travel time between them. A gap
    /// smaller than this (but still non-negative) is flagged as *tight*.
    var minimumGap: TimeInterval

    /// Extra lead time (seconds) required before a flight, on top of the travel
    /// time to reach the airport — time to check in, clear security and reach
    /// the gate. Applied only when the *next* item is a flight (Req 4.5).
    var flightLeadTime: TimeInterval

    init(minimumGap: TimeInterval = ScheduleBuffer.defaultMinimumGap,
         flightLeadTime: TimeInterval = ScheduleBuffer.defaultFlightLeadTime) {
        self.minimumGap = minimumGap
        self.flightLeadTime = flightLeadTime
    }

    /// Default comfortable gap: 15 minutes.
    static let defaultMinimumGap: TimeInterval = 15 * 60

    /// Default airport lead time before a flight: 90 minutes.
    static let defaultFlightLeadTime: TimeInterval = 90 * 60

    /// The default buffer (15-minute gap, 90-minute flight lead).
    static let `default` = ScheduleBuffer()
}

// MARK: - Verdict

/// How comfortable a single gap is.
nonisolated enum ScheduleVerdict: Hashable, Sendable {
    /// Enough slack: the gap covers travel plus the full buffer.
    case ok
    /// Doable but tight: the gap covers travel but leaves less than the buffer.
    case tight
    /// Impossible as scheduled: the next item starts before the previous ends
    /// plus the required travel (and flight lead, if applicable).
    case overlap
}

// MARK: - Gap result

/// The evaluation of the gap *after* a given entry (i.e. between it and the
/// next entry). Attached to the preceding entry's id so the view can render a
/// warning on that row / its following leg.
nonisolated struct ScheduleGap: Hashable, Sendable, Identifiable {
    /// The entry this gap follows; also the stable identity of the gap.
    let afterEntryID: UUID
    /// The entry this gap precedes.
    let beforeEntryID: UUID
    /// The verdict for this gap.
    let verdict: ScheduleVerdict
    /// Slack remaining after subtracting travel (and any flight lead) from the
    /// available time. Negative when the items overlap; compared against
    /// `minimumGap` to separate *tight* from *ok*.
    let slackSeconds: TimeInterval
    /// Whether the next entry is a flight, so the flight lead time was applied.
    let nextIsFlight: Bool

    var id: UUID { afterEntryID }
}

// MARK: - Input

/// A lightweight, framework-free view of a timeline item for evaluation. The
/// view model maps each `TimelineEntry` to one of these (reading `start`/`end`
/// and whether the source is a flight). A point-in-time item has `end == nil`
/// and is treated as ending at its `start`.
nonisolated struct ScheduleItem: Hashable, Sendable, Identifiable {
    let id: UUID
    /// Start instant (UTC).
    let start: Date
    /// End instant (UTC); `nil` for a point-in-time item.
    let end: Date?
    /// Whether this item is a flight, which requires the flight lead buffer
    /// when it is the *next* item in a pair (Req 4.5).
    let isFlight: Bool

    init(id: UUID, start: Date, end: Date? = nil, isFlight: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.isFlight = isFlight
    }

    /// The effective end of this item: its `end`, or its `start` when it is a
    /// point in time.
    var effectiveEnd: Date { end ?? start }
}

// MARK: - Evaluator

/// Pure schedule evaluation. No state, no dependencies — just a function from
/// ordered items + travel times + buffer to per-gap verdicts.
nonisolated enum ScheduleEvaluator {

    /// Evaluates every consecutive pair of `items`, returning one `ScheduleGap`
    /// per pair.
    ///
    /// For a pair `(prev, next)`:
    /// - `available = next.start - prev.effectiveEnd` (a point item ends at its
    ///   start, Req 4.5).
    /// - `required = travel + (next.isFlight ? buffer.flightLeadTime : 0)`,
    ///   where `travel` is `travelTimes[prev.id]` (keyed to the preceding entry,
    ///   as produced by the view model's legs) or `0` when unknown.
    /// - `slack = available - required`.
    /// - Verdict: `overlap` when `slack < 0`; `tight` when
    ///   `0 <= slack < buffer.minimumGap`; otherwise `ok`.
    ///
    /// When the travel time for a leg is unknown (no entry in `travelTimes`),
    /// travel is treated as `0`. This keeps the day view from inventing a
    /// warning out of a missing estimate while still catching a hard overlap
    /// (and still applying the flight lead when the next item is a flight).
    ///
    /// - Parameters:
    ///   - items: the day's items in chronological order.
    ///   - travelTimes: per-leg travel seconds, keyed to the *preceding* item's
    ///     id (matching `DayItineraryViewModel.TravelLeg.afterEntryID`).
    ///   - buffer: the configurable buffer (defaults to ``ScheduleBuffer/default``).
    /// - Returns: one gap per consecutive pair, in order.
    static func evaluate(
        items: [ScheduleItem],
        travelTimes: [UUID: TimeInterval],
        buffer: ScheduleBuffer = .default
    ) -> [ScheduleGap] {
        guard items.count >= 2 else { return [] }

        var gaps: [ScheduleGap] = []
        gaps.reserveCapacity(items.count - 1)

        for index in 0..<(items.count - 1) {
            let prev = items[index]
            let next = items[index + 1]

            let available = next.start.timeIntervalSince(prev.effectiveEnd)
            let travel = travelTimes[prev.id] ?? 0
            let lead = next.isFlight ? buffer.flightLeadTime : 0
            let required = travel + lead
            let slack = available - required

            let verdict: ScheduleVerdict
            if slack < 0 {
                verdict = .overlap
            } else if slack < buffer.minimumGap {
                verdict = .tight
            } else {
                verdict = .ok
            }

            gaps.append(
                ScheduleGap(
                    afterEntryID: prev.id,
                    beforeEntryID: next.id,
                    verdict: verdict,
                    slackSeconds: slack,
                    nextIsFlight: next.isFlight
                )
            )
        }

        return gaps
    }
}

// MARK: - User-facing warning text

nonisolated extension ScheduleGap {
    /// Whether this gap warrants a visible warning (anything other than `ok`).
    var isWarning: Bool { verdict != .ok }

    /// A short, user-facing warning label, or `nil` when the gap is fine.
    /// Phrased from the perspective of the row the warning sits on.
    var warningText: String? {
        switch verdict {
        case .ok:
            return nil
        case .tight:
            return nextIsFlight ? "Tight connection to flight" : "Tight connection"
        case .overlap:
            return nextIsFlight ? "Too tight to make the flight" : "Overlaps previous"
        }
    }
}
