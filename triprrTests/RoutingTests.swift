//
//  RoutingTests.swift
//  triprrTests
//
//  Unit tests for routing: the deterministic mock service (plausible,
//  repeatable estimates and the configurable error/offline path), the
//  concurrency-safe cache reusing estimates for repeated legs, estimate
//  formatting, and the day view model's leg computation + graceful degrade
//  when routing is unavailable (Req 4.4, 4.6).
//

import Testing
import Foundation
import CoreLocation
@testable import triprr

struct RoutingTests {

    // MARK: - Fixtures

    private var tokyoStation: Place {
        Place(name: "Tokyo Station", latitude: 35.6812, longitude: 139.7671,
              timeZoneIdentifier: "Asia/Tokyo")
    }
    private var sensoji: Place {
        Place(name: "Sensō-ji", latitude: 35.7148, longitude: 139.7967,
              timeZoneIdentifier: "Asia/Tokyo")
    }

    // MARK: - Mock service

    @Test func mockProducesPlausibleDeterministicEstimate() async throws {
        let service = MockRoutingService()
        let a = try await service.estimate(from: tokyoStation, to: sensoji, mode: .automobile)
        let b = try await service.estimate(from: tokyoStation, to: sensoji, mode: .automobile)

        // Deterministic: same inputs, same output.
        #expect(a == b)
        #expect(a.travelTime > 0)
        #expect(a.distance > 0)
        #expect(a.mode == .automobile)
    }

    @Test func mockWalkingIsSlowerThanDriving() async throws {
        let service = MockRoutingService()
        let driving = try await service.estimate(from: tokyoStation, to: sensoji, mode: .automobile)
        let walking = try await service.estimate(from: tokyoStation, to: sensoji, mode: .walking)

        // Same distance, slower mode → more time.
        #expect(walking.travelTime > driving.travelTime)
    }

    @Test func mockThrowsConfiguredError() async {
        let service = MockRoutingService(errorToThrow: .offline)
        await #expect(throws: RoutingError.offline) {
            _ = try await service.estimate(from: tokyoStation, to: sensoji, mode: .automobile)
        }
    }

    // MARK: - Cache

    @Test func estimatesMatchForSameCoordinatesRegardlessOfPlaceID() async throws {
        // The MapKit service caches by (origin coord, destination coord, mode),
        // not by Place.id. Two Place values at the same coordinates (but with
        // different random ids) must therefore produce the same estimate from a
        // deterministic service — which is what makes the coordinate-keyed cache
        // safe to reuse across distinct Place instances.
        let service = MockRoutingService()
        let originA = Place(name: "A", latitude: 35.6812, longitude: 139.7671)
        let originB = Place(name: "A copy", latitude: 35.6812, longitude: 139.7671)
        #expect(originA.id != originB.id)

        let a = try await service.estimate(from: originA, to: sensoji, mode: .automobile)
        let b = try await service.estimate(from: originB, to: sensoji, mode: .automobile)
        #expect(a == b)
    }

    // MARK: - Formatting

    @Test func estimateFormatsCompactLabel() {
        let estimate = RouteEstimate(travelTime: 15 * 60, distance: 3_200, mode: .automobile)
        #expect(estimate.timeLabel == "15 min")
        // Distance label is locale-aware; just assert it mentions the mode and time.
        #expect(estimate.compactLabel.contains("15 min"))
        #expect(estimate.compactLabel.contains("Driving"))
    }

    @Test func estimateFormatsHoursAndMinutes() {
        let estimate = RouteEstimate(travelTime: 80 * 60, distance: 50_000, mode: .automobile)
        #expect(estimate.timeLabel == "1 hr 20 min")
    }

    // MARK: - View model leg computation + graceful degrade

    @MainActor
    @Test func viewModelBuildsLegsBetweenPlacedEntries() {
        let trip = SampleData.makeTokyoTrip()
        let vm = DayItineraryViewModel(trip: trip, routing: MockRoutingService())

        // Select the activities day (the day after the flight's arrival).
        if let activityDay = vm.dayStarts.first(where: { day in
            !vm.entries(forDayStarting: day).compactMap(vm.activity(for:)).isEmpty
        }) {
            vm.selectedDayStart = activityDay
        }

        let entries = vm.entriesForSelectedDay
        let placed = entries.filter { $0.place != nil }
        let legs = vm.travelLegsForSelectedDay

        // A leg between every consecutive pair of placed entries (same place
        // pairs are skipped, so at most placed-1).
        #expect(legs.count <= max(0, placed.count - 1))
        #expect(legs.count >= 1)
    }

    @MainActor
    @Test func unavailableRoutingDegradesGracefully() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = DayItineraryViewModel(trip: trip, routing: MockRoutingService(errorToThrow: .offline))

        if let activityDay = vm.dayStarts.first(where: { day in
            !vm.entries(forDayStarting: day).compactMap(vm.activity(for:)).isEmpty
        }) {
            vm.selectedDayStart = activityDay
        }

        await vm.loadTravelEstimates()

        let legs = vm.travelLegsForSelectedDay
        #expect(!legs.isEmpty)
        // Every leg resolves to .unavailable rather than throwing out of the
        // day assembly (Req 4.6).
        for leg in legs {
            #expect(vm.state(for: leg) == .unavailable)
        }
    }

    @MainActor
    @Test func estimatesResolveAndCacheAcrossReload() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = DayItineraryViewModel(trip: trip, routing: MockRoutingService())

        if let activityDay = vm.dayStarts.first(where: { day in
            !vm.entries(forDayStarting: day).compactMap(vm.activity(for:)).isEmpty
        }) {
            vm.selectedDayStart = activityDay
        }

        await vm.loadTravelEstimates()
        let legs = vm.travelLegsForSelectedDay
        #expect(!legs.isEmpty)

        var resolved: [UUID: RouteEstimate] = [:]
        for leg in legs {
            if case .estimate(let estimate) = vm.state(for: leg) {
                resolved[leg.id] = estimate
            }
        }
        #expect(resolved.count == legs.count)

        // A second load reuses the cached states unchanged.
        await vm.loadTravelEstimates()
        for leg in legs {
            if case .estimate(let estimate) = vm.state(for: leg) {
                #expect(resolved[leg.id] == estimate)
            } else {
                Issue.record("Leg \(leg.id) lost its cached estimate on reload")
            }
        }
    }
}
