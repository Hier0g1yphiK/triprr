//
//  SuggestionService.swift
//  triprr
//
//  Suggestion value types + the discovery protocol behind the smart-suggestions
//  feature (Req 5). The request captures everything the user chooses in the
//  form: how much time they have (a preset or a custom duration), when they
//  start, the area to search, their interests and their pace. A `Suggestion` is
//  a single candidate stop; discovery returns the raw set and the planner
//  (task 7.3) time-fits them. Behind a `Sendable` protocol so previews/tests
//  substitute a deterministic mock and the MapKit implementation (task 7.2)
//  plugs in without any UI change. Empty results and errors are kept distinct
//  so the view model can surface distinct states (Req 5.6).
//

import Foundation
import CoreLocation

/// A preset amount of time the user has available, plus a custom option.
///
/// The request carries the resolved `TimeInterval`; this enum is the UI-facing
/// choice that maps onto it. `custom` leaves the duration to the form's custom
/// picker (Req 5.1).
nonisolated enum AvailableTimePreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case coupleHours
    case halfDay
    case fullDay
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coupleHours: "A couple of hours"
        case .halfDay: "Half day"
        case .fullDay: "Full day"
        case .custom: "Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .coupleHours: "clock"
        case .halfDay: "clock.badge"
        case .fullDay: "sun.max"
        case .custom: "slider.horizontal.3"
        }
    }

    /// The duration this preset resolves to, or `nil` for `custom` (the form
    /// supplies a custom duration instead).
    var duration: TimeInterval? {
        switch self {
        case .coupleHours: 2 * 3600
        case .halfDay: 4 * 3600
        case .fullDay: 8 * 3600
        case .custom: nil
        }
    }
}

/// The input to a suggestion request: the area to explore, when and for how
/// long, the user's interests and their pace (Req 5.1).
nonisolated struct SuggestionRequest: Equatable, Sendable {
    /// The city/area to search; defaults from the trip or day's place.
    var area: Place
    /// UTC instant the plan starts at. Displayed in the area's local zone.
    var start: Date
    /// Resolved available time, in seconds (from a preset or a custom value).
    var available: TimeInterval
    /// Optional interests to seed discovery; empty means a sensible default mix.
    var interests: [Interest]
    /// How densely to plan the day.
    var pace: Pace

    init(
        area: Place,
        start: Date,
        available: TimeInterval,
        interests: [Interest],
        pace: Pace
    ) {
        self.area = area
        self.start = start
        self.available = available
        self.interests = interests
        self.pace = pace
    }
}

/// A single suggested stop returned by discovery.
///
/// Arrival/departure times and `distanceFromPrevious` are assigned by the
/// planner once a set is time-fitted (task 7.3); discovery leaves them `nil`.
nonisolated struct Suggestion: Identifiable, Hashable, Sendable {
    let id: UUID
    /// The place to visit; carries its own coordinate and (resolved) zone.
    var place: Place
    /// The activity category this maps to, for display and visit-duration.
    var category: ActivityCategory
    /// A short, user-facing summary line (Req 5.4).
    var summary: String
    /// The estimated time spent at this stop, in seconds.
    var estimatedVisitDuration: TimeInterval
    /// Straight-line/route distance from the previous stop, assigned by the
    /// planner (Req 5.4). `nil` until planned, or for the first stop.
    var distanceFromPrevious: CLLocationDistance?
    /// UTC arrival instant, assigned by the planner. `nil` until planned.
    var arrivalTime: Date?
    /// UTC departure instant, assigned by the planner. `nil` until planned.
    var departureTime: Date?

    init(
        id: UUID = UUID(),
        place: Place,
        category: ActivityCategory,
        summary: String,
        estimatedVisitDuration: TimeInterval,
        distanceFromPrevious: CLLocationDistance? = nil,
        arrivalTime: Date? = nil,
        departureTime: Date? = nil
    ) {
        self.id = id
        self.place = place
        self.category = category
        self.summary = summary
        self.estimatedVisitDuration = estimatedVisitDuration
        self.distanceFromPrevious = distanceFromPrevious
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
    }
}

/// Errors a suggestion request can surface. The view model keeps these distinct
/// from the empty (no-results) state (Req 5.6).
nonisolated enum SuggestionError: Error, Equatable {
    /// No network connection.
    case offline
    /// The request failed for another reason.
    case failed
}

extension SuggestionError {
    /// A short, user-facing explanation suitable for the error state.
    var message: String {
        switch self {
        case .offline:
            "You appear to be offline. Suggestions need a connection — try again once you're back online."
        case .failed:
            "Couldn't load suggestions right now. Please try again."
        }
    }
}

/// Discovers candidate stops for a suggestion request.
///
/// Networked implementations throw `SuggestionError`; the UI depends only on
/// this protocol so the concrete provider can change freely. Planning (fitting
/// candidates to the available time) is a separate step (task 7.3).
nonisolated protocol SuggestionService: Sendable {
    func suggestions(for request: SuggestionRequest) async throws -> [Suggestion]
}

// TODO: real discovery — `MapKitSuggestionService` (task 7.2) satisfies this
// protocol using `MKLocalSearch` scoped to the request's area. No UI change is
// required because the view model talks to the protocol, not a concrete type.
