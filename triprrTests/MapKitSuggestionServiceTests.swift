//
//  MapKitSuggestionServiceTests.swift
//  triprrTests
//
//  Unit tests for the pure, network-free helpers of `MapKitSuggestionService`
//  (Req 5.2): default-interest selection when none are chosen, interest→MapKit
//  mapping (query term + POI categories + resulting activity category/visit
//  duration), the MKMapItem→Suggestion mapping (name/coordinate/zone fallback,
//  discovery leaves planning fields nil), and merge de-duplication + capping.
//  The live `MKLocalSearch` path is deliberately NOT exercised here — it would
//  hit the network and be non-deterministic.
//

import Testing
import Foundation
import CoreLocation
import MapKit
@testable import triprr

struct MapKitSuggestionServiceTests {

    private var tokyoArea: Place {
        Place(
            name: "Tokyo",
            latitude: 35.6812, longitude: 139.7671,
            address: "Tokyo, Japan",
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    private func request(interests: [Interest]) -> SuggestionRequest {
        SuggestionRequest(
            area: tokyoArea,
            start: Date(),
            available: 4 * 3600,
            interests: interests,
            pace: .relaxed
        )
    }

    // MARK: - Default interests (Req 5.2)

    @Test func noInterestsFallsBackToDefaultMix() {
        let effective = MapKitSuggestionService.effectiveInterests(for: request(interests: []))
        #expect(Set(effective) == Set([.landmarks, .food, .museums]))
    }

    @Test func chosenInterestsAreUsedVerbatim() {
        let effective = MapKitSuggestionService.effectiveInterests(
            for: request(interests: [.nightlife, .shopping])
        )
        #expect(effective == [.nightlife, .shopping])
    }

    // MARK: - Interest → MapKit mapping

    @Test func everyInterestHasAQueryAndCategoryMapping() {
        for interest in Interest.allCases {
            #expect(!interest.searchQuery.isEmpty)
            // Food/museums/outdoors/nightlife/shopping/landmarks all have at
            // least one POI category to prefer.
            #expect(!interest.pointOfInterestCategories.isEmpty)
        }
    }

    @Test func visitDurationsArePositivePerCategory() {
        for category in ActivityCategory.allCases {
            #expect(category.baseVisitDuration > 0)
        }
        // A museum visit is longer than a landmark stop, matching the design.
        #expect(ActivityCategory.museum.baseVisitDuration > ActivityCategory.landmark.baseVisitDuration)
    }

    // MARK: - MKMapItem → Suggestion mapping

    private func mapItem(name: String, lat: Double, lon: Double) -> MKMapItem {
        let location = CLLocation(latitude: lat, longitude: lon)
        let item = MKMapItem(location: location, address: nil)
        item.name = name
        return item
    }

    @Test func mapsMapItemIntoDiscoverySuggestion() throws {
        let item = mapItem(name: "City Art Museum", lat: 35.7000, lon: 139.7700)
        let suggestion = try #require(
            MapKitSuggestionService.suggestion(from: item, interest: .museums, area: tokyoArea)
        )

        #expect(suggestion.place.name == "City Art Museum")
        #expect(suggestion.category == .museum)
        #expect(suggestion.estimatedVisitDuration == ActivityCategory.museum.baseVisitDuration)
        // Discovery only: the planner (task 7.3) fills these in later.
        #expect(suggestion.arrivalTime == nil)
        #expect(suggestion.departureTime == nil)
        #expect(suggestion.distanceFromPrevious == nil)
    }

    @Test func inheritsAreaTimeZoneWhenMapItemHasNone() throws {
        let item = mapItem(name: "Old Town Landmark", lat: 35.6900, lon: 139.7600)
        // A bare map item built from a coordinate carries no time zone.
        #expect(item.timeZone == nil)

        let suggestion = try #require(
            MapKitSuggestionService.suggestion(from: item, interest: .landmarks, area: tokyoArea)
        )
        #expect(suggestion.place.timeZoneIdentifier == tokyoArea.timeZoneIdentifier)
    }

    // Note: whether a nameless `MKMapItem` yields a usable name is up to MapKit
    // (it may reverse-geocode one), so the "drop unnamed stops" guard isn't
    // deterministically testable without the network and is left to the live
    // path. The guard itself (`place.name != "Unknown place"`) is a cheap check.

    // MARK: - Merge / de-duplicate / cap

    private func suggestion(name: String, lat: Double, lon: Double, category: ActivityCategory = .landmark) -> Suggestion {
        Suggestion(
            place: Place(name: name, latitude: lat, longitude: lon, timeZoneIdentifier: "Asia/Tokyo"),
            category: category,
            summary: name,
            estimatedVisitDuration: category.baseVisitDuration
        )
    }

    @Test func deduplicatesSameNameAtSameCoordinate() {
        let a = suggestion(name: "Sensō-ji", lat: 35.7148, lon: 139.7967)
        // Same place discovered by a second interest search (different id, same
        // name + coordinate) collapses to one.
        let aAgain = suggestion(name: "SENSŌ-JI", lat: 35.71482, lon: 139.79668, category: .outdoors)
        let b = suggestion(name: "Tokyo Tower", lat: 35.6586, lon: 139.7454)

        let result = MapKitSuggestionService.deduplicatedAndCapped([a, aAgain, b])
        #expect(result.count == 2)
        // First occurrence wins (stable order).
        #expect(result.first?.id == a.id)
    }

    @Test func capsResultCount() {
        let many = (0..<(MapKitSuggestionService.resultCap + 10)).map { i in
            suggestion(name: "Stop \(i)", lat: 35.0 + Double(i) * 0.01, lon: 139.0 + Double(i) * 0.01)
        }
        let result = MapKitSuggestionService.deduplicatedAndCapped(many)
        #expect(result.count == MapKitSuggestionService.resultCap)
    }

    // MARK: - Region

    @Test func regionIsCentredOnAreaWithSensibleSpan() {
        let region = MapKitSuggestionService.region(around: tokyoArea)
        #expect(region.center.latitude == tokyoArea.latitude)
        #expect(region.center.longitude == tokyoArea.longitude)
        #expect(region.span.latitudeDelta > 0)
        #expect(region.span.longitudeDelta > 0)
    }
}
