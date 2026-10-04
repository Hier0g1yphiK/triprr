//
//  SuggestionsViewModel.swift
//  triprr
//
//  Backs the smart-suggestions screen. Holds the request form state — available
//  time (a preset or a custom duration), start time, the area (defaulting to
//  the trip's primary destination), selected interests and pace (Req 5.1) — and
//  runs a small load state machine with distinct idle / loading / loaded /
//  empty / error states (Req 5.6). `requestSuggestions()` calls the injected
//  `SuggestionService` to discover candidates, then time-fits them with the
//  pure `SuggestionPlanner` (task 7.3) using a travel-time closure backed by the
//  `RoutingService` (falling back to a straight-line estimate so planning never
//  hard-fails), and maps the outcome: a non-empty planned set → `loaded`, zero
//  candidates/zero that fit → `empty`, a thrown discovery error/offline →
//  `error`. The view can then show each stop's summary, duration and
//  distance-from-previous (Req 5.4) and add it to the day in one tap (Req 5.5).
//  Discovery is the MapKit service (task 7.2) and time-fitting is the planner
//  (task 7.3); this VM composes them behind the `SuggestionService` and
//  `RoutingService` protocols.
//

import Foundation
import CoreLocation
import SwiftData

@MainActor
@Observable
final class SuggestionsViewModel {
    /// The load state machine. `empty` (no results) and `error` are distinct so
    /// the view can show the right message (Req 5.6).
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([Suggestion])
        case empty
        case error(String)
    }

    // MARK: - Request form state (Req 5.1)

    /// The chosen available-time preset. When `.custom`, `customDuration` is used.
    var timePreset: AvailableTimePreset = .halfDay {
        didSet { if timePreset != .custom { customDuration = timePreset.duration ?? customDuration } }
    }
    /// The custom available time (seconds), used when `timePreset == .custom`.
    var customDuration: TimeInterval = 4 * 3600
    /// When the plan starts (UTC; displayed in the area's local zone).
    var startTime: Date = Date()
    /// The area to explore; defaults from the trip's primary destination.
    var area: Place?
    /// The user's selected interests (empty means a default mix).
    var interests: [Interest] = []
    /// How densely to plan the day.
    var pace: Pace = .relaxed

    // MARK: - Load state

    private(set) var state: LoadState = .idle

    /// Tracks the ids of suggestions already added to the day, so a row can show
    /// clear "Added" feedback and avoid creating a duplicate activity (Req 5.5).
    private(set) var addedSuggestionIDs: Set<UUID> = []

    private var suggestions: any SuggestionService
    private var routing: any RoutingService

    /// The area's zone for displaying the start time, falling back to current.
    var areaTimeZone: TimeZone {
        area?.timeZone ?? .current
    }

    /// The resolved available time, from the preset or the custom value.
    var resolvedAvailableTime: TimeInterval {
        timePreset.duration ?? customDuration
    }

    init(
        area: Place? = nil,
        suggestions: any SuggestionService = MockSuggestionService(),
        routing: any RoutingService = MockRoutingService()
    ) {
        self.area = area
        self.suggestions = suggestions
        self.routing = routing
    }

    /// Builds a VM defaulting the area to the trip's primary destination.
    convenience init(
        trip: Trip,
        suggestions: any SuggestionService = MockSuggestionService(),
        routing: any RoutingService = MockRoutingService()
    ) {
        let primary = trip.destinations
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .place
        self.init(area: primary, suggestions: suggestions, routing: routing)
    }

    /// Injects the services from the environment once the view appears, since
    /// the service container isn't available at `init`.
    func use(suggestions: any SuggestionService, routing: any RoutingService) {
        self.suggestions = suggestions
        self.routing = routing
    }

    // MARK: - Derived form helpers

    /// Whether a request can be made (an area is required to search).
    var canRequest: Bool {
        area != nil && state != .loading
    }

    /// Whether a request is currently running.
    var isLoading: Bool { state == .loading }

    /// The loaded suggestions, if any (otherwise empty).
    var loadedSuggestions: [Suggestion] {
        if case let .loaded(items) = state { return items }
        return []
    }

    /// The error message to show, if the last request failed.
    var errorMessage: String? {
        if case let .error(message) = state { return message }
        return nil
    }

    /// Toggles an interest in the selection.
    func toggle(_ interest: Interest) {
        if let index = interests.firstIndex(of: interest) {
            interests.remove(at: index)
        } else {
            interests.append(interest)
        }
    }

    func isSelected(_ interest: Interest) -> Bool {
        interests.contains(interest)
    }

    // MARK: - Request

    /// Builds a `SuggestionRequest` from the current form, discovers candidates
    /// via the service, time-fits them with `SuggestionPlanner` (travel time
    /// backed by routing with a straight-line fallback), and maps the outcome
    /// into the load state. Zero candidates — or none that fit the window —
    /// become the distinct `empty` state; a thrown discovery error/offline
    /// becomes `error` (Req 5.4, 5.6).
    func requestSuggestions() async {
        guard let area else { return }

        // A fresh request clears any prior "added" feedback.
        addedSuggestionIDs.removeAll()

        let request = SuggestionRequest(
            area: area,
            start: startTime,
            available: resolvedAvailableTime,
            interests: interests,
            pace: pace
        )

        state = .loading
        do {
            let candidates = try await suggestions.suggestions(for: request)
            guard !candidates.isEmpty else {
                state = .empty
                return
            }
            let plan = await buildPlan(candidates: candidates, request: request)
            state = plan.stops.isEmpty ? .empty : .loaded(plan.stops)
        } catch let error as SuggestionError {
            state = .error(error.message)
        } catch {
            state = .error(SuggestionError.failed.message)
        }
    }

    // MARK: - Planning (routing-backed, straight-line fallback)

    /// Time-fits `candidates` with the pure `SuggestionPlanner`. The planner's
    /// injected travel-time closure is synchronous, so inter-stop travel is
    /// pre-resolved here: a travel matrix is built once for all candidate pairs
    /// using the `RoutingService`, each cell falling back to a straight-line
    /// estimate when routing is unavailable (offline/no route). The closure then
    /// reads the matrix, so planning never hard-fails on routing (Req 5.3).
    func buildPlan(
        candidates: [Suggestion],
        request: SuggestionRequest
    ) async -> SuggestionPlan {
        let travelMatrix = await travelTimeMatrix(for: candidates)

        return SuggestionPlanner.plan(
            candidates: candidates,
            request: request,
            travelTime: { from, to in
                travelMatrix[PairKey(from.id, to.id)]
                    ?? Self.straightLineTravelTime(from: from.place, to: to.place)
            }
        )
    }

    /// Builds travel seconds for every ordered candidate pair. Routing is tried
    /// first (one directed estimate per pair); any failure degrades to a
    /// straight-line estimate for that pair, so a single offline/no-route leg
    /// doesn't fail the whole plan (Req 5.3, 4.6).
    private func travelTimeMatrix(
        for candidates: [Suggestion]
    ) async -> [PairKey: TimeInterval] {
        var matrix: [PairKey: TimeInterval] = [:]
        for from in candidates {
            for to in candidates where from.id != to.id {
                let seconds: TimeInterval
                do {
                    let estimate = try await routing.estimate(
                        from: from.place, to: to.place, mode: .automobile
                    )
                    seconds = estimate.travelTime
                } catch {
                    seconds = Self.straightLineTravelTime(from: from.place, to: to.place)
                }
                matrix[PairKey(from.id, to.id)] = seconds
            }
        }
        return matrix
    }

    /// A straight-line travel-time fallback: great-circle distance padded for
    /// real roads, divided by a representative in-city driving speed. Keeps
    /// planning self-contained when routing can't answer.
    private static func straightLineTravelTime(from: Place, to: Place) -> TimeInterval {
        let distance = from.location.distance(from: to.location) * 1.3
        let metersPerSecond = 11.0 // ~40 km/h in-city, matching the routing mock.
        return distance / metersPerSecond
    }

    /// A directed key into the travel matrix.
    private struct PairKey: Hashable {
        let from: UUID
        let to: UUID
        init(_ from: UUID, _ to: UUID) { self.from = from; self.to = to }
    }

    // MARK: - Add to day (Req 5.5)

    /// Whether `suggestion` has already been added to the day this session.
    func isAdded(_ suggestion: Suggestion) -> Bool {
        addedSuggestionIDs.contains(suggestion.id)
    }

    /// One-tap add: creates an `Activity` on `trip` for the suggested stop and
    /// inserts it via `context`, so it appears in the itinerary immediately
    /// (Req 5.5). Title/category/place come from the suggestion; the time range
    /// uses the planned arrival/departure when the planner assigned them, else
    /// the request's start time plus the estimated visit duration. The new
    /// activity is appended with the next `sortOrder`, matching the itinerary
    /// editor (task 6.2). Idempotent per session via `addedSuggestionIDs`.
    func addToDay(_ suggestion: Suggestion, trip: Trip, context: ModelContext) {
        guard !addedSuggestionIDs.contains(suggestion.id) else { return }

        let start = suggestion.arrivalTime ?? startTime
        let end = suggestion.departureTime
            ?? start.addingTimeInterval(suggestion.estimatedVisitDuration)

        let activity = Activity(
            title: suggestion.place.name,
            category: suggestion.category,
            startDate: start,
            endDate: end,
            timeZoneIdentifier: suggestion.place.timeZoneIdentifier
                ?? area?.timeZoneIdentifier,
            place: suggestion.place,
            notes: suggestion.summary,
            sortOrder: nextSortOrder(for: trip),
            trip: trip
        )
        context.insert(activity)
        try? context.save()

        addedSuggestionIDs.insert(suggestion.id)
    }

    /// The next `sortOrder` to append a new activity after the trip's existing
    /// ones, so an added suggestion reads at the end of its slot until the user
    /// reorders — consistent with the itinerary editor (task 6.2).
    private func nextSortOrder(for trip: Trip) -> Int {
        (trip.activities.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Resets back to the idle state (e.g. when the form changes).
    func reset() {
        if state != .loading { state = .idle }
    }

    #if DEBUG
    /// Preview/testing seam: drives the load state directly so a preview can
    /// render a terminal state (loaded/empty/error) deterministically, without
    /// relying on an async request resolving after the snapshot is taken. The
    /// empty and error previews use this so their distinct result sections are
    /// visible in a static snapshot (Req 5.6).
    func setStateForPreview(_ state: LoadState) {
        self.state = state
    }
    #endif
}
