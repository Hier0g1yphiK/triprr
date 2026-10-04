//
//  triprrTests.swift
//  triprrTests
//
//  Created by John McCullough on 03/10/2026.
//
//  Test suites are organised by subject in separate files:
//  - DateTimeZoneTests: UTC storage / local-zone display logic.
//  Further suites (ScheduleEvaluator, SuggestionPlanner) are added with their
//  features.
//

import Testing
@testable import triprr

/// Smoke test confirming the test target links against the app module.
struct TriprrSmokeTests {
    @Test func sampleTripsBuild() async throws {
        await MainActor.run {
            let trips = SampleData.makeSampleTrips()
            #expect(trips.count == 3)
        }
    }
}
