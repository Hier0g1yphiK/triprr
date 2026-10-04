//
//  SuggestionPlannerTests.swift
//  triprrTests
//
//  Unit tests for the pure `SuggestionPlanner` (Req 5.3): nearest-neighbour
//  ordering determinism, pace scaling of per-category visit durations, travel
//  time inserted between stops via the injected closure, the available-window
//  cutoff (stops dropped when they don't fit), opening-hours skip/shift
//  behaviour, and arrival/departure/distance assignment correctness. The
//  planner is framework-free, so these run with plain value fixtures — no
//  MapKit, no RoutingService, no network.
//

import Testing
import Foundation
import CoreLocation
@testable import triprr

struct SuggestionPlannerTests {

    // MARK: - Fixtures

    /// A fixed start instant so every assertion is deterministic.
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    /// The search area origin (used by nearest-neighbour ordering). Stops are
    /// placed east of it along the equator so east/west distance dominates.
    private var area: Place {
        Place(name: "Area", latitude: 0, longitude: 0, timeZoneIdentifier: "UTC")
    }

    /// Builds a stop at a given longitude offset (degrees east of the area) so
    /// the geometry — and therefore ordering and straight-line distance — is
    /// controlled. A fixed `id` keeps nearest-neighbour tie-breaks stable.
    private func stop(
        id: UUID,
        name: String,
        category: ActivityCategory,
        lonDegrees: Double
    ) -> Suggestion {
        let place = Place(
            id: UUID(),
            name: name,
            latitude: 0,
            longitude: lonDegrees,
            timeZoneIdentifier: "UTC"
        )
        return Suggestion(
            id: id,
            place: place,
            category: category,
            summary: name,
            estimatedVisitDuration: category.baseVisitDuration
        )
    }

    /// Deterministic UUIDs for predictable tie-breaking in ordering tests.
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    private func request(available: TimeInterval, pace: Pace) -> SuggestionRequest {
        SuggestionRequest(
            area: area,
            start: start,
            available: available,
            interests: [],
            pace: pace
        )
    }

    /// A constant travel-time closure, in minutes.
    private func constantTravel(minutes: TimeInterval) -> (Suggestion, Suggestion) -> TimeInterval {
        { _, _ in minutes * 60 }
    }

    // MARK: - Ordering determinism (Req 5.3)

    @Test func ordersStopsByNearestNeighbourFromArea() {
        // Placed out of order; nearest-neighbour from the area (lon 0) should
        // visit them west→east: near (1°), mid (2°), far (3°).
        let near = stop(id: uuid(1), name: "Near", category: .landmark, lonDegrees: 1)
        let far = stop(id: uuid(2), name: "Far", category: .landmark, lonDegrees: 3)
        let mid = stop(id: uuid(3), name: "Mid", category: .landmark, lonDegrees: 2)

        // Generous window + zero travel so every stop is kept and only ordering
        // is under test.
        let plan = SuggestionPlanner.plan(
            candidates: [far, mid, near],
            request: request(available: 24 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 0)
        )

        #expect(plan.stops.map(\.place.name) == ["Near", "Mid", "Far"])
    }

    @Test func orderingIsStableAcrossInputPermutations() {
        let a = stop(id: uuid(1), name: "A", category: .landmark, lonDegrees: 1)
        let b = stop(id: uuid(2), name: "B", category: .landmark, lonDegrees: 2)
        let c = stop(id: uuid(3), name: "C", category: .landmark, lonDegrees: 3)
        let req = request(available: 24 * 3600, pace: .packed)
        let travel = constantTravel(minutes: 0)

        let order1 = SuggestionPlanner.plan(candidates: [a, b, c], request: req, travelTime: travel).stops.map(\.id)
        let order2 = SuggestionPlanner.plan(candidates: [c, b, a], request: req, travelTime: travel).stops.map(\.id)
        let order3 = SuggestionPlanner.plan(candidates: [b, c, a], request: req, travelTime: travel).stops.map(\.id)

        #expect(order1 == order2)
        #expect(order2 == order3)
    }

    // MARK: - Pace scaling of visit durations (Req 5.3)

    @Test func visitDurationScalesWithPace() {
        #expect(
            SuggestionPlanner.visitDuration(for: .museum, pace: .relaxed)
            == ActivityCategory.museum.baseVisitDuration * Pace.relaxed.durationMultiplier
        )
        #expect(
            SuggestionPlanner.visitDuration(for: .museum, pace: .packed)
            == ActivityCategory.museum.baseVisitDuration * Pace.packed.durationMultiplier
        )
        // Packed is shorter than relaxed for the same category.
        #expect(
            SuggestionPlanner.visitDuration(for: .food, pace: .packed)
            < SuggestionPlanner.visitDuration(for: .food, pace: .relaxed)
        )
    }

    @Test func plannedDepartureReflectsPaceScaledVisit() {
        let single = stop(id: uuid(1), name: "Museum", category: .museum, lonDegrees: 1)

        let relaxed = SuggestionPlanner.plan(
            candidates: [single],
            request: request(available: 24 * 3600, pace: .relaxed),
            travelTime: constantTravel(minutes: 0)
        )
        let packed = SuggestionPlanner.plan(
            candidates: [single],
            request: request(available: 24 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 0)
        )

        let relaxedVisit = relaxed.stops[0].departureTime!.timeIntervalSince(relaxed.stops[0].arrivalTime!)
        let packedVisit = packed.stops[0].departureTime!.timeIntervalSince(packed.stops[0].arrivalTime!)

        #expect(relaxedVisit == ActivityCategory.museum.baseVisitDuration * Pace.relaxed.durationMultiplier)
        #expect(packedVisit == ActivityCategory.museum.baseVisitDuration * Pace.packed.durationMultiplier)
        #expect(packedVisit < relaxedVisit)
        // The planner also stamps the scaled visit onto estimatedVisitDuration.
        #expect(packed.stops[0].estimatedVisitDuration == packedVisit)
    }

    // MARK: - Travel time inserted between stops (Req 5.3)

    @Test func travelTimeIsInsertedBetweenStops() {
        // Two landmarks; packed landmark visit = 45m × 0.8 = 36m each.
        let first = stop(id: uuid(1), name: "First", category: .landmark, lonDegrees: 1)
        let second = stop(id: uuid(2), name: "Second", category: .landmark, lonDegrees: 2)

        let plan = SuggestionPlanner.plan(
            candidates: [first, second],
            request: request(available: 24 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 20)
        )

        #expect(plan.stops.count == 2)

        let visit = ActivityCategory.landmark.baseVisitDuration * Pace.packed.durationMultiplier

        // First stop: no travel, starts at the request start.
        #expect(plan.stops[0].arrivalTime == start)
        #expect(plan.stops[0].departureTime == start.addingTimeInterval(visit))

        // Second stop: arrival = first.departure + 20m travel.
        let expectedSecondArrival = plan.stops[0].departureTime!.addingTimeInterval(20 * 60)
        #expect(plan.stops[1].arrivalTime == expectedSecondArrival)
        #expect(plan.stops[1].departureTime == expectedSecondArrival.addingTimeInterval(visit))
    }

    @Test func firstStopChargesNoTravel() {
        let only = stop(id: uuid(1), name: "Only", category: .food, lonDegrees: 1)
        let plan = SuggestionPlanner.plan(
            candidates: [only],
            request: request(available: 24 * 3600, pace: .relaxed),
            // Travel would be huge if (wrongly) charged for the first stop.
            travelTime: constantTravel(minutes: 500)
        )
        #expect(plan.stops[0].arrivalTime == start)
        #expect(plan.stops[0].distanceFromPrevious == nil)
    }

    // MARK: - Available-window cutoff (Req 5.3)

    @Test func dropsStopsThatDoNotFitTheWindow() {
        // Three landmarks, packed visit 36m each, zero travel → 108m total to
        // fit all three. A 90-minute window fits only two.
        let a = stop(id: uuid(1), name: "A", category: .landmark, lonDegrees: 1)
        let b = stop(id: uuid(2), name: "B", category: .landmark, lonDegrees: 2)
        let c = stop(id: uuid(3), name: "C", category: .landmark, lonDegrees: 3)

        let plan = SuggestionPlanner.plan(
            candidates: [a, b, c],
            request: request(available: 90 * 60, pace: .packed),
            travelTime: constantTravel(minutes: 0)
        )

        #expect(plan.stops.map(\.place.name) == ["A", "B"])
        // Every kept stop finishes within the window.
        #expect(plan.stops.allSatisfy { $0.departureTime! <= plan.windowEnd })
        #expect(plan.windowEnd == start.addingTimeInterval(90 * 60))
    }

    @Test func emptyWhenNothingFits() {
        // A museum (packed 72m) cannot fit a 10-minute window.
        let museum = stop(id: uuid(1), name: "Museum", category: .museum, lonDegrees: 1)
        let plan = SuggestionPlanner.plan(
            candidates: [museum],
            request: request(available: 10 * 60, pace: .packed),
            travelTime: constantTravel(minutes: 0)
        )
        #expect(plan.isEmpty)
        #expect(plan.end == start)
    }

    @Test func emptyCandidatesYieldEmptyPlan() {
        let plan = SuggestionPlanner.plan(
            candidates: [],
            request: request(available: 8 * 3600, pace: .relaxed),
            travelTime: constantTravel(minutes: 10)
        )
        #expect(plan.isEmpty)
        #expect(plan.start == start)
        #expect(plan.windowEnd == start.addingTimeInterval(8 * 3600))
    }

    // MARK: - Opening-hours handling (Req 5.3)

    @Test func deferArrivalUntilOpening() {
        // A landmark that would be reached at the start, but doesn't open until
        // 30 minutes in → arrival should shift to the opening time.
        let s = stop(id: uuid(1), name: "Opens Late", category: .landmark, lonDegrees: 1)
        let open = start.addingTimeInterval(30 * 60)
        let close = start.addingTimeInterval(6 * 3600)

        let plan = SuggestionPlanner.plan(
            candidates: [s],
            request: request(available: 8 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 0),
            openingHours: { _ in OpeningHours(open: open, close: close) }
        )

        #expect(plan.stops.count == 1)
        #expect(plan.stops[0].arrivalTime == open)
        let visit = ActivityCategory.landmark.baseVisitDuration * Pace.packed.durationMultiplier
        #expect(plan.stops[0].departureTime == open.addingTimeInterval(visit))
    }

    @Test func skipClosedStopButKeepLaterOpenOne() {
        // First candidate is already closed by the start; it should be skipped
        // and the next (open) one kept, with no travel charged for the skip.
        let closed = stop(id: uuid(1), name: "Closed", category: .landmark, lonDegrees: 1)
        let open = stop(id: uuid(2), name: "Open", category: .landmark, lonDegrees: 2)

        let plan = SuggestionPlanner.plan(
            candidates: [closed, open],
            request: request(available: 8 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 15),
            openingHours: { suggestion in
                suggestion.place.name == "Closed"
                    ? OpeningHours(open: start.addingTimeInterval(-2 * 3600),
                                   close: start.addingTimeInterval(-3600)) // closed before start
                    : nil
            }
        )

        #expect(plan.stops.map(\.place.name) == ["Open"])
        // The kept stop is the first *kept* stop → no predecessor → no travel,
        // starts at the request start.
        #expect(plan.stops[0].arrivalTime == start)
        #expect(plan.stops[0].distanceFromPrevious == nil)
    }

    @Test func deferredArrivalStillRespectsWindowCutoff() {
        // Opening is so late that even a packed visit wouldn't finish in time.
        let s = stop(id: uuid(1), name: "Too Late", category: .museum, lonDegrees: 1)
        let plan = SuggestionPlanner.plan(
            candidates: [s],
            request: request(available: 2 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 0),
            openingHours: { _ in
                OpeningHours(open: start.addingTimeInterval(110 * 60),  // opens at 1h50m
                             close: start.addingTimeInterval(8 * 3600))
            }
        )
        // Museum packed visit = 72m; 110m + 72m = 182m > 120m window → dropped.
        #expect(plan.isEmpty)
    }

    // MARK: - Distance assignment (Req 5.4 / 5.3)

    @Test func assignsStraightLineDistanceFromPrevious() {
        let first = stop(id: uuid(1), name: "First", category: .landmark, lonDegrees: 1)
        let second = stop(id: uuid(2), name: "Second", category: .landmark, lonDegrees: 2)

        let plan = SuggestionPlanner.plan(
            candidates: [first, second],
            request: request(available: 24 * 3600, pace: .packed),
            travelTime: constantTravel(minutes: 5)
        )

        #expect(plan.stops[0].distanceFromPrevious == nil)

        let expected = SuggestionPlanner.straightLineDistance(from: first.place, to: second.place)
        let actual = try! #require(plan.stops[1].distanceFromPrevious)
        #expect(abs(actual - expected) < 0.001)
        // One degree of longitude at the equator is ~111 km; two stops 1° apart.
        #expect(actual > 100_000)
        #expect(actual < 120_000)
        // Plan total distance aggregates the legs (only the second has one).
        #expect(abs(plan.totalDistance - expected) < 0.001)
    }

    @Test func negativeTravelTimesAreClampedToZero() {
        let a = stop(id: uuid(1), name: "A", category: .landmark, lonDegrees: 1)
        let b = stop(id: uuid(2), name: "B", category: .landmark, lonDegrees: 2)

        let plan = SuggestionPlanner.plan(
            candidates: [a, b],
            request: request(available: 24 * 3600, pace: .packed),
            travelTime: { _, _ in -500 }
        )

        // Second stop arrives exactly at the first's departure (travel clamped).
        #expect(plan.stops[1].arrivalTime == plan.stops[0].departureTime)
    }
}
