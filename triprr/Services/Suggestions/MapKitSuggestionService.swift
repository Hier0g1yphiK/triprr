//
//  MapKitSuggestionService.swift
//  triprr
//
//  The live discovery half of the smart-suggestions feature (Req 5.2). It finds
//  candidate stops near the request's area with `MKLocalSearch`, one search per
//  chosen interest, scoped to a region built around the area's coordinate. Each
//  interest maps to a point-of-interest category filter and a natural-language
//  query term; with no interests chosen it uses a sensible default mix
//  (landmarks + food + museums). Map items are turned into `Suggestion`s —
//  discovery only: arrival/departure times and distance-from-previous are left
//  nil for the planner (task 7.3) to assign. Searches run concurrently, results
//  are merged, de-duplicated and capped. Failures map to the shared typed
//  `SuggestionError` (offline → .offline, otherwise .failed). It sits behind the
//  existing `SuggestionService` protocol, so the view model and UI are unchanged.
//

import Foundation
import CoreLocation
import MapKit

/// `MKLocalSearch`-backed discovery of candidate stops for a suggestion
/// request. `Sendable`: it holds only value configuration and does its work in
/// local tasks, so it can be shared across the concurrency domain.
nonisolated struct MapKitSuggestionService: SuggestionService {
    /// Radius, in meters, of the search region built around the area's
    /// coordinate. A few km keeps results walkable/driveable within a day while
    /// staying inside one city rather than the whole metro area.
    static let searchRadius: CLLocationDistance = 5_000

    /// Upper bound on returned candidates. Discovery over-fetches so the planner
    /// (task 7.3) has choice; this caps the merged set so the UI and planner
    /// don't churn on hundreds of items.
    static let resultCap = 40

    init() {}

    func suggestions(for request: SuggestionRequest) async throws -> [Suggestion] {
        let interests = Self.effectiveInterests(for: request)
        let region = Self.region(around: request.area)

        // One MKLocalSearch per interest, run concurrently; a failure in any
        // single search propagates as a typed SuggestionError.
        let groups: [[Suggestion]] = try await withThrowingTaskGroup(
            of: [Suggestion].self
        ) { group in
            for interest in interests {
                group.addTask {
                    try await Self.search(interest: interest, in: region, area: request.area)
                }
            }
            var collected: [[Suggestion]] = []
            for try await result in group {
                collected.append(result)
            }
            return collected
        }

        let merged = groups.flatMap { $0 }
        return Self.deduplicatedAndCapped(merged)
    }

    // MARK: - Discovery (per interest)

    /// Runs a single region-scoped `MKLocalSearch` for one interest and maps the
    /// map items into `Suggestion`s for that interest's category.
    private static func search(
        interest: Interest,
        in region: MKCoordinateRegion,
        area: Place
    ) async throws -> [Suggestion] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = interest.searchQuery
        request.region = region
        // Prefer POI results in the interest's categories where MapKit supports
        // it; the natural-language query covers the rest.
        let categories = interest.pointOfInterestCategories
        if !categories.isEmpty {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { mapItem in
                Self.suggestion(from: mapItem, interest: interest, area: area)
            }
        } catch {
            throw mapError(error)
        }
    }

    /// Maps an `MKLocalSearch`/MapKit failure to a typed `SuggestionError`,
    /// matching how the sibling MapKit services classify offline vs other
    /// failures (Req 5.6).
    private static func mapError(_ error: Error) -> SuggestionError {
        if (error as NSError).domain == NSURLErrorDomain {
            return .offline
        }
        return .failed
    }

    // MARK: - Mapping (pure)

    /// Turns a single `MKMapItem` into a discovery `Suggestion` for the given
    /// interest, or `nil` when the item has no usable name. Pure (no network);
    /// unit-tested directly. Arrival/departure and distance are left nil for the
    /// planner (task 7.3); the time zone comes from the map item when MapKit
    /// resolves it, otherwise it inherits the area's zone as a reasonable
    /// default (the planner/zone backfill refines it later).
    static func suggestion(
        from mapItem: MKMapItem,
        interest: Interest,
        area: Place
    ) -> Suggestion? {
        var place = Place(mapItem: mapItem)
        guard place.name != "Unknown place" else { return nil }
        if place.timeZoneIdentifier == nil {
            place.timeZoneIdentifier = area.timeZoneIdentifier
        }

        let category = interest.activityCategory
        return Suggestion(
            place: place,
            category: category,
            summary: summary(for: mapItem, category: category),
            estimatedVisitDuration: category.baseVisitDuration
        )
    }

    /// A short, user-facing summary line from the map item: its POI category's
    /// readable name when available, else its address, else the category's
    /// display name. Pure; unit-tested.
    static func summary(for mapItem: MKMapItem, category: ActivityCategory) -> String {
        if let poi = mapItem.pointOfInterestCategory, let label = poi.readableName {
            return label
        }
        let address = mapItem.addressRepresentations?
            .fullAddress(includingRegion: true, singleLine: true)
            ?? mapItem.address?.fullAddress
        if let address, !address.isEmpty {
            return address
        }
        return category.displayName
    }

    // MARK: - Interests → search inputs (pure)

    /// The interests to actually search for: the request's interests, or a
    /// sensible default mix (landmarks + food + museums) when none are chosen.
    /// Pure; unit-tested.
    static func effectiveInterests(for request: SuggestionRequest) -> [Interest] {
        request.interests.isEmpty
            ? [.landmarks, .food, .museums]
            : request.interests
    }

    // MARK: - Region

    /// A region centred on the area, sized by ``searchRadius``, used to scope
    /// each `MKLocalSearch` to the city rather than the whole world.
    static func region(around area: Place) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: area.coordinate,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
    }

    // MARK: - Merge / de-duplicate / cap

    /// Merges results across interests, dropping duplicates (same name at the
    /// same ~11 m coordinate cell) and capping the count. Pure; unit-tested.
    static func deduplicatedAndCapped(_ suggestions: [Suggestion]) -> [Suggestion] {
        var seen = Set<DedupKey>()
        var result: [Suggestion] = []
        result.reserveCapacity(min(suggestions.count, resultCap))
        for suggestion in suggestions {
            let key = DedupKey(suggestion.place)
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
            if result.count == resultCap { break }
        }
        return result
    }

    /// Identity for de-duplication: a case-folded name plus the coordinate
    /// quantised to ~1e-4 degrees (~11 m) so the same POI returned by two
    /// interest searches collapses to one.
    private struct DedupKey: Hashable {
        let name: String
        let lat: Int
        let lon: Int

        init(_ place: Place) {
            self.name = place.name.lowercased()
            func quantise(_ value: Double) -> Int { Int((value * 10_000).rounded()) }
            self.lat = quantise(place.latitude)
            self.lon = quantise(place.longitude)
        }
    }
}

// MARK: - Interest → MapKit mapping

nonisolated extension Interest {
    /// The natural-language query term seeding this interest's `MKLocalSearch`.
    var searchQuery: String {
        switch self {
        case .food: "restaurants"
        case .museums: "museums"
        case .outdoors: "parks"
        case .nightlife: "bars"
        case .shopping: "shopping"
        case .landmarks: "landmarks"
        }
    }

    /// The point-of-interest categories to prefer for this interest. Empty where
    /// MapKit has no close category and the query term carries the search.
    var pointOfInterestCategories: [MKPointOfInterestCategory] {
        switch self {
        case .food:
            [.restaurant, .cafe, .bakery, .foodMarket]
        case .museums:
            [.museum]
        case .outdoors:
            [.park, .nationalPark, .beach]
        case .nightlife:
            [.nightlife]
        case .shopping:
            [.store]
        case .landmarks:
            [.landmark, .castle, .fortress]
        }
    }
}

// MARK: - ActivityCategory → visit duration

nonisolated extension ActivityCategory {
    /// A reasonable base time spent at a stop of this category, in seconds.
    /// Discovery stamps this on each `Suggestion`; the planner (task 7.3) scales
    /// it by pace. Mirrors the design's tunable constants (museum ~90m,
    /// landmark ~45m, meal ~75m, outdoors ~60m, …).
    var baseVisitDuration: TimeInterval {
        switch self {
        case .museum: 90 * 60
        case .landmark: 45 * 60
        case .food: 75 * 60
        case .outdoors: 60 * 60
        case .shopping: 60 * 60
        case .nightlife: 90 * 60
        case .transport: 15 * 60
        case .other: 60 * 60
        }
    }
}

// MARK: - MKPointOfInterestCategory → readable name

nonisolated extension MKPointOfInterestCategory {
    /// A short readable label for the common suggestion categories, used in a
    /// suggestion's summary when MapKit tags the map item with a POI category.
    var readableName: String? {
        switch self {
        case .restaurant: "Restaurant"
        case .cafe: "Café"
        case .bakery: "Bakery"
        case .foodMarket: "Food market"
        case .museum: "Museum"
        case .park: "Park"
        case .nationalPark: "National park"
        case .beach: "Beach"
        case .nightlife: "Nightlife"
        case .store: "Shop"
        case .landmark: "Landmark"
        case .castle: "Castle"
        case .fortress: "Fortress"
        default: nil
        }
    }
}
