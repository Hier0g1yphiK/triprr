//
//  MockSuggestionService.swift
//  triprr
//
//  A deterministic mock for the running-app fallback, previews and tests. It
//  returns a stable set of plausible candidate stops near the requested area,
//  filtered to the chosen interests, so the suggestions screen always has
//  content without touching the network. It can be configured to return an
//  empty set or to throw, which lets previews/tests exercise the distinct
//  empty vs error states (Req 5.6). The MapKit-backed discovery lands in task
//  7.2 and plugs in behind the same `SuggestionService` protocol.
//

import Foundation
import CoreLocation

/// A deterministic `SuggestionService` for previews, tests and as the live
/// fallback until `MapKitSuggestionService` (task 7.2) ships.
nonisolated struct MockSuggestionService: SuggestionService {
    /// When set, every request throws this error (to exercise the error path).
    var errorToThrow: SuggestionError?
    /// When true, requests return no candidates (to exercise the empty state).
    var returnsEmpty: Bool
    /// Simulated latency so previews/tests can observe the loading state.
    var delay: Duration

    init(
        errorToThrow: SuggestionError? = nil,
        returnsEmpty: Bool = false,
        delay: Duration = .zero
    ) {
        self.errorToThrow = errorToThrow
        self.returnsEmpty = returnsEmpty
        self.delay = delay
    }

    func suggestions(for request: SuggestionRequest) async throws -> [Suggestion] {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let errorToThrow { throw errorToThrow }
        if returnsEmpty { return [] }

        let candidates = Self.candidates(near: request.area)

        // Filter to the chosen interests' categories; with none chosen, return
        // a default landmark/food-leaning mix (all candidates).
        let wantedCategories = Set(request.interests.map(\.activityCategory))
        let filtered = wantedCategories.isEmpty
            ? candidates
            : candidates.filter { wantedCategories.contains($0.category) }

        return filtered
    }

    // MARK: - Deterministic candidates

    /// Builds a stable set of candidate stops offset from the area's
    /// coordinate, so distances between them are small and realistic. IDs are
    /// derived deterministically from the area so repeated calls match.
    private static func candidates(near area: Place) -> [Suggestion] {
        let specs: [(name: String, category: ActivityCategory, summary: String, visit: TimeInterval, dLat: Double, dLon: Double)] = [
            ("City Art Museum", .museum, "A compact collection worth an hour or two.", 90 * 60, 0.004, 0.003),
            ("Old Town Landmark", .landmark, "The classic photo stop in the historic quarter.", 45 * 60, -0.003, 0.005),
            ("Central Market Food Hall", .food, "Street food and local specialities under one roof.", 75 * 60, 0.002, -0.004),
            ("Riverside Park", .outdoors, "Green space for a stroll between stops.", 60 * 60, 0.006, 0.001),
            ("Boutique Shopping Lane", .shopping, "Independent shops along a pedestrian street.", 60 * 60, -0.004, -0.002),
            ("Rooftop Jazz Bar", .nightlife, "Drinks and live music once the sun's down.", 90 * 60, 0.001, 0.006),
        ]

        return specs.map { spec in
            let place = Place(
                id: deterministicID(area: area, name: spec.name),
                name: spec.name,
                latitude: area.latitude + spec.dLat,
                longitude: area.longitude + spec.dLon,
                address: spec.name,
                timeZoneIdentifier: area.timeZoneIdentifier
            )
            return Suggestion(
                id: deterministicID(area: area, name: spec.name),
                place: place,
                category: spec.category,
                summary: spec.summary,
                estimatedVisitDuration: spec.visit
            )
        }
    }

    /// A stable UUID for an (area, name) pair so the mock is deterministic.
    private static func deterministicID(area: Place, name: String) -> UUID {
        var hasher = Hasher()
        hasher.combine(area.id)
        hasher.combine(name)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        // Spread the 64-bit hash across the 128-bit UUID.
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (UInt64(i) * 8)) & 0xFF)
            bytes[i + 8] = UInt8((hash >> (UInt64(7 - i) * 8)) & 0xFF)
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
