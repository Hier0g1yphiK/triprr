//
//  FlightLookupTests.swift
//  triprrTests
//
//  Unit tests for the mock flight lookup service and the editor's "look up"
//  action: deterministic sample data, synthesis for unknown numbers, the
//  configurable error/offline path, and mapping a result into the form while
//  keeping manual entry available (Req 2.4, 2.5).
//

import Testing
import Foundation
@testable import triprr

struct FlightLookupTests {

    // A fixed reference date (2026-10-15 12:00 UTC) to query against.
    private var referenceDate: Date {
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = 2026; comps.month = 10; comps.day = 15; comps.hour = 12
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // MARK: - Mock service

    @Test func recognisesSampleFlightNumber() async throws {
        let service = MockFlightLookupService()
        let result = try await service.lookup(
            FlightLookupQuery(flightNumber: "BA005", date: referenceDate)
        )

        #expect(result.airline == "British Airways")
        #expect(result.flightNumber == "BA005")
        #expect(result.departureAirport.timeZoneIdentifier == "Europe/London")
        #expect(result.arrivalAirport.timeZoneIdentifier == "Asia/Tokyo")
        #expect(result.scheduledArrival > result.scheduledDeparture)
        #expect(result.terminal == "5")
    }

    @Test func sampleLookupIsCaseAndWhitespaceInsensitive() async throws {
        let service = MockFlightLookupService()
        let result = try await service.lookup(
            FlightLookupQuery(flightNumber: "  ba005 ", date: referenceDate)
        )
        #expect(result.airline == "British Airways")
    }

    @Test func sampleDepartureLandsAtExpectedLocalTime() async throws {
        let service = MockFlightLookupService()
        let result = try await service.lookup(
            FlightLookupQuery(flightNumber: "BA005", date: referenceDate)
        )
        // BA005 departs 11:30 local London time.
        let london = TimeZone(identifier: "Europe/London")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = london
        let hour = cal.component(.hour, from: result.scheduledDeparture)
        let minute = cal.component(.minute, from: result.scheduledDeparture)
        #expect(hour == 11)
        #expect(minute == 30)
    }

    @Test func synthesisesResultForUnknownNumber() async throws {
        let service = MockFlightLookupService()
        let result = try await service.lookup(
            FlightLookupQuery(flightNumber: "ZZ999", date: referenceDate)
        )
        #expect(result.flightNumber == "ZZ999")
        #expect(!result.airline.isEmpty)
        #expect(result.scheduledArrival > result.scheduledDeparture)
    }

    @Test func emptyNumberThrowsNotFound() async {
        let service = MockFlightLookupService()
        await #expect(throws: FlightLookupError.notFound) {
            _ = try await service.lookup(
                FlightLookupQuery(flightNumber: "   ", date: referenceDate)
            )
        }
    }

    @Test func configurableErrorIsThrown() async {
        let service = MockFlightLookupService(errorToThrow: .offline)
        await #expect(throws: FlightLookupError.offline) {
            _ = try await service.lookup(
                FlightLookupQuery(flightNumber: "BA005", date: referenceDate)
            )
        }
    }

    // MARK: - Editor action

    @Test @MainActor func lookUpFillsFormOnSuccess() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = FlightEditViewModel(
            mode: .create(trip),
            flightLookup: MockFlightLookupService()
        )
        vm.flightNumber = "BA005"

        await vm.lookUp()

        #expect(vm.lookupState == .filled)
        #expect(vm.airline == "British Airways")
        #expect(vm.departureAirport?.timeZoneIdentifier == "Europe/London")
        #expect(vm.arrivalAirport?.timeZoneIdentifier == "Asia/Tokyo")
        #expect(vm.departureZoneIdentifier == "Europe/London")
        #expect(vm.arrivalZoneIdentifier == "Asia/Tokyo")
        #expect(vm.terminal == "5")
    }

    @Test @MainActor func lookUpOnFailureKeepsManualEntry() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = FlightEditViewModel(
            mode: .create(trip),
            flightLookup: MockFlightLookupService(errorToThrow: .offline)
        )
        vm.flightNumber = "BA005"
        vm.airline = "Typed Airline"

        await vm.lookUp()

        // A clear error is surfaced and the user's manual input is untouched.
        #expect(vm.lookupErrorMessage != nil)
        #expect(vm.airline == "Typed Airline")
        #expect(vm.flightNumber == "BA005")
    }

    @Test @MainActor func cannotLookUpWithoutFlightNumber() {
        let trip = SampleData.makeTokyoTrip()
        let vm = FlightEditViewModel(mode: .create(trip))
        vm.flightNumber = "   "
        #expect(vm.canLookUp == false)
    }
}
