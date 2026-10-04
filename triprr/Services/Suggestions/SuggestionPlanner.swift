//
//  SuggestionPlanner.swift
//  triprr
//
//  The pure, dependency-free time-fitter behind the smart-suggestions feature
//  (Req 5.3). Given the raw candidate stops discovered by a `SuggestionService`
//  (task 7.1/7.2) and the user's `SuggestionRequest`, it orders a sensible
//  visiting sequence and walks it from `request.start`, assigning each kept
//  stop an `arrivalTime`, a `departureTime` and a `distanceFromPrevious`, so the
//  returned set fits inside the available time window.
//
//  It touches no frameworks beyond value types — no SwiftData, no MapKit, no
//  SwiftUI, no RoutingService. Inter-stop *travel time* is supplied by an
//  injected closure so the planner stays pure and is unit-tested directly
//  (Req 11.4); the caller (the view model, task 7.4) backs that closure with
//  `RoutingService` or a straight-line fallback. Straight-line *distance* is
//  computed from the coordinates with CoreLocation, which is a value-level
//  calculation (not a service) and keeps the output self-contained.
//
//  CoreLocation is used only for the straight-line distance helper; the time
//  logic is plain `Date`/`TimeInterval` arithmetic.
//

import Foundation
import CoreLocation

// MARK: - Opening hours

/// A single open window for a candidate stop, expressed as a half-open UTC
/// interval `[open, close)`. The planner's opening-hours policy (below) uses it
/// to decide whether to defer arrival to opening or skip a stop that is already
/// closed by the time it would be reached. `nil` (the default) means "assume
/// open" — the common case, since MapKit often exposes no hours.
nonisolated struct OpeningHours: Hashable, Sendable {
    /// Earliest UTC instant the stop can be entered.
    var open: Date
    /// UTC instant the stop closes; arriving at or after this skips the stop.
    var close: Date

    init(open: Date, close: Date) {
        self.open = open
        self.close = close
    }

    /// Whether `instant` falls within `[open, close)`.
    func contains(_ instant: Date) -> Bool {
        instant >= open && instant < close
    }
}

// MARK: - Plan

/// The time-fitted result: the ordered subset of candidates that fit, each with
/// `arrivalTime`, `departureTime` and `distanceFromPrevious` assigned, plus the
/// window the plan was fitted into. A small wrapper (rather than a bare array)
/// so the view model (task 7.4) has the start/end and total travel to hand
/// without recomputing them.
nonisolated struct SuggestionPlan: Equatable, Sendable {
    /// The kept stops in visiting order, with planning fields filled in.
    var stops: [Suggestion]
    /// The instant the plan starts (mirrors `request.start`).
    var start: Date
    /// The hard end of the window the plan was fitted into
    /// (`request.start + request.available`).
    var windowEnd: Date

    init(stops: [Suggestion], start: Date, windowEnd: Date) {
        self.stops = stops
        self.start = start
        self.windowEnd = windowEnd
    }

    /// The departure instant of the last kept stop, or `start` when empty.
    var end: Date { stops.last?.departureTime ?? start }

    /// Total travel distance across the kept legs, in metres.
    var totalDistance: CLLocationDistance {
        stops.reduce(0) { $0 + ($1.distanceFromPrevious ?? 0) }
    }

    /// Whether nothing fit.
    var isEmpty: Bool { stops.isEmpty }
}

// MARK: - Planner

/// Pure time-fitting of discovered suggestions into the user's available
/// window. Stateless — a single function from `(candidates, request, injected
/// estimates)` to a `SuggestionPlan`.
///
/// ## Algorithm (deterministic and documented)
///
/// 1. **Order** the candidates into a visiting sequence by *nearest-neighbour*
///    starting from the request's `area` coordinate: repeatedly pick the
///    nearest not-yet-visited candidate (straight-line distance), breaking ties
///    by the stop's `id` so the ordering is stable and repeatable. This needs
///    no clock and no travel estimates, so ordering alone is deterministic.
///
/// 2. **Walk** the ordered sequence from `request.start`, maintaining a running
///    `cursor` (the instant the traveller becomes free) and the previous kept
///    stop:
///    - `travel` = injected `travelTime(previous, candidate)` (0 for the first
///      stop, which has no predecessor).
///    - tentative `arrival = cursor + travel`.
///    - **Opening hours** (see policy below) may *defer* the arrival to opening
///      or cause the stop to be *skipped*.
///    - `visit = category.baseVisitDuration × pace.durationMultiplier` — packed
///      shortens, relaxed lengthens (Req 5.3).
///    - `departure = arrival + visit`.
///
/// 3. **Window cutoff**: a stop is kept only if its `departure ≤ windowEnd`
///    (`request.start + request.available`). The walk stops adding further
///    stops once a candidate would push past the window; remaining candidates
///    are not force-fitted (Req 5.3 — "a set that fits within the available
///    time").
///
/// 4. Each kept stop records `distanceFromPrevious` (straight-line metres from
///    the previous kept stop; `nil` for the first), `arrivalTime` and
///    `departureTime`. The cursor advances to the kept stop's `departure`.
///
/// ## Opening-hours policy (deterministic)
///
/// For a candidate whose `openingHours(candidate)` is non-nil:
/// - If tentative arrival is **before** `open`, **defer** arrival to `open`
///   (then re-check the window against the deferred departure).
/// - If tentative arrival is **at or after** `close`, the stop is already
///   closed — **skip** it and move on to the next candidate (the cursor does
///   not advance; no travel is charged for a skipped stop).
/// - Otherwise the stop is open on arrival and is scheduled as normal.
///
/// A `nil` opening-hours result means "assume open" (MapKit frequently exposes
/// no hours), so unconstrained candidates are never skipped on hours grounds.
nonisolated enum SuggestionPlanner {

    /// Fits `candidates` into the request's window, assigning arrival/departure
    /// and distance to each kept stop.
    ///
    /// - Parameters:
    ///   - candidates: the raw discovered suggestions (planning fields ignored
    ///     on input and overwritten on output).
    ///   - request: the user's request — supplies `start`, `available` and
    ///     `pace`, and its `area` seeds the nearest-neighbour ordering.
    ///   - travelTime: injected travel seconds between two stops. The planner
    ///     never calls MapKit/RoutingService itself; the caller backs this with
    ///     real directions or a straight-line fallback. Returns a non-negative
    ///     interval; negative values are clamped to 0.
    ///   - openingHours: injected opening window for a candidate, or `nil` to
    ///     assume it is always open. Defaults to always-open.
    /// - Returns: the fitted plan (ordered kept stops + window).
    static func plan(
        candidates: [Suggestion],
        request: SuggestionRequest,
        travelTime: (Suggestion, Suggestion) -> TimeInterval,
        openingHours: (Suggestion) -> OpeningHours? = { _ in nil }
    ) -> SuggestionPlan {
        let windowEnd = request.start.addingTimeInterval(max(0, request.available))

        guard !candidates.isEmpty else {
            return SuggestionPlan(stops: [], start: request.start, windowEnd: windowEnd)
        }

        let ordered = orderedByNearestNeighbour(candidates, from: request.area.coordinate)

        var kept: [Suggestion] = []
        var cursor = request.start
        var previous: Suggestion?

        for candidate in ordered {
            // Travel from the previous kept stop (none for the first stop).
            let travel: TimeInterval
            if let previous {
                travel = max(0, travelTime(previous, candidate))
            } else {
                travel = 0
            }

            var arrival = cursor.addingTimeInterval(travel)

            // Opening-hours policy: defer to opening, or skip if already closed.
            if let hours = openingHours(candidate) {
                if arrival < hours.open {
                    arrival = hours.open
                } else if arrival >= hours.close {
                    // Closed by the time we'd arrive — skip without advancing.
                    continue
                }
            }

            let visit = visitDuration(for: candidate.category, pace: request.pace)
            let departure = arrival.addingTimeInterval(visit)

            // Window cutoff: only keep the stop if it finishes within the window.
            guard departure <= windowEnd else { continue }

            var planned = candidate
            planned.arrivalTime = arrival
            planned.departureTime = departure
            planned.estimatedVisitDuration = visit
            planned.distanceFromPrevious = previous.map {
                straightLineDistance(from: $0.place, to: candidate.place)
            }

            kept.append(planned)
            cursor = departure
            previous = planned
        }

        return SuggestionPlan(stops: kept, start: request.start, windowEnd: windowEnd)
    }

    // MARK: - Visit duration

    /// The pace-scaled visit duration for a category: the category's base
    /// duration multiplied by the pace multiplier (packed < 1 shortens,
    /// relaxed > 1 lengthens). Pure and side-effect free (Req 5.3).
    static func visitDuration(for category: ActivityCategory, pace: Pace) -> TimeInterval {
        category.baseVisitDuration * pace.durationMultiplier
    }

    // MARK: - Ordering

    /// Orders candidates by nearest-neighbour from `origin`, breaking distance
    /// ties by `id` so the sequence is deterministic. Pure: no clock, no travel
    /// estimates — purely geometric.
    private static func orderedByNearestNeighbour(
        _ candidates: [Suggestion],
        from origin: CLLocationCoordinate2D
    ) -> [Suggestion] {
        var remaining = candidates
        var ordered: [Suggestion] = []
        ordered.reserveCapacity(remaining.count)

        var currentLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        while !remaining.isEmpty {
            // Pick the nearest remaining candidate; ties broken by id.
            var bestIndex = 0
            var bestDistance = currentLocation.distance(from: remaining[0].place.location)

            for index in 1..<remaining.count {
                let distance = currentLocation.distance(from: remaining[index].place.location)
                if distance < bestDistance
                    || (distance == bestDistance && remaining[index].id.uuidString < remaining[bestIndex].id.uuidString) {
                    bestDistance = distance
                    bestIndex = index
                }
            }

            let next = remaining.remove(at: bestIndex)
            ordered.append(next)
            currentLocation = next.place.location
        }

        return ordered
    }

    // MARK: - Distance

    /// Straight-line (great-circle) distance between two places, in metres.
    /// Used for `distanceFromPrevious`; a value-level calculation, not a
    /// service call.
    static func straightLineDistance(from: Place, to: Place) -> CLLocationDistance {
        from.location.distance(from: to.location)
    }
}
