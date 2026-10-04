//
//  OfflineBehaviorTests.swift
//  triprrTests
//
//  Offline-behavior pass (Req 10.4, 10.5). Two guarantees are asserted here
//  for every online-only feature — flight lookup, suggestions discovery and
//  routing/directions — using the existing Mock services configured to throw
//  `.offline`:
//
//  1. The feature surfaces a *correct, distinct* offline state: flight lookup
//     shows a clear error while manual entry stays intact; suggestions land in
//     the distinct `.error` state (not `.empty`); routing legs resolve to
//     `.unavailable` and the day still renders every item.
//  2. No saved data is lost or corrupted: an offline failure leaves everything
//     the user typed untouched and does NOT insert or delete any SwiftData
//     model (counts unchanged), proving "without data loss" (Req 10.5).
//
//  Viewing/editing saved data itself has no network dependency — it is all
//  SwiftData `ModelContext` reads/writes — which the `savedDataIsEditableOffline`
//  test exercises directly against an in-memory container with no services
//  involved (Req 10.4).
//

import Testing
import Foundation
import SwiftData
@testable import triprr

@MainActor
struct OfflineBehaviorTests {

    // MARK: - Fixtures

    /// A fresh, empty in-memory container retained for the test's lifetime (a
    /// `ModelContext` does not keep its container alive on its own).
    private let container = SampleData.emptyContainer()

    private func makeContext() -> ModelContext { container.mainContext }

    private var tokyoArea: Place {
        Place(
            name: "Tokyo",
            latitude: 35.6812, longitude: 139.7671,
            address: "Tokyo, Japan",
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    /// Total number of persisted models across every entity type. Used to prove
    /// an offline failure neither inserts nor deletes anything (Req 10.5).
    private func modelCounts(in context: ModelContext) throws -> [String: Int] {
        [
            "Trip": try context.fetchCount(FetchDescriptor<Trip>()),
            "Flight": try context.fetchCount(FetchDescriptor<Flight>()),
            "Stay": try context.fetchCount(FetchDescriptor<Stay>()),
            "Booking": try context.fetchCount(FetchDescriptor<Booking>()),
            "Activity": try context.fetchCount(FetchDescriptor<Activity>()),
            "Note": try context.fetchCount(FetchDescriptor<Note>()),
            "LinkItem": try context.fetchCount(FetchDescriptor<LinkItem>()),
        ]
    }

    // MARK: - Req 10.4 — saved data is fully viewable/editable offline

    /// Viewing and editing saved data touches no service: it is pure SwiftData.
    /// Seeding a trip and then editing items of every kind (and deleting one)
    /// succeeds here with no network available because none is involved at all.
    @Test func savedDataIsEditableOffline() throws {
        let context = makeContext()

        // "Save" a representative trip (as if done while online, earlier).
        let trip = SampleData.makeTokyoTrip()
        context.insert(trip)
        try context.save()

        // VIEW: a fresh fetch returns the saved graph with its items intact.
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let saved = try #require(trips.first)
        #expect(saved.flights.count == 1)
        #expect(saved.stays.count == 1)
        #expect(saved.bookings.count == 1)
        #expect(saved.activities.count == 3)
        #expect(saved.notes.count == 1)
        #expect(saved.links.count == 1)

        // EDIT: mutate items of each kind and save — no connection needed.
        saved.name = "Tokyo Adventure (edited offline)"
        saved.flights.first?.seat = "1A"
        saved.stays.first?.confirmationNumber = "OFFLINE-EDIT"
        saved.bookings.first?.title = "Edited Show"
        saved.activities.first?.isDone = true
        saved.notes.first?.text = "Edited note"
        saved.links.first?.title = "Edited link"
        try context.save()

        // A fresh fetch reflects every edit.
        let reloaded = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
        #expect(reloaded.name == "Tokyo Adventure (edited offline)")
        #expect(reloaded.flights.first?.seat == "1A")
        #expect(reloaded.stays.first?.confirmationNumber == "OFFLINE-EDIT")
        #expect(reloaded.bookings.first?.title == "Edited Show")
        #expect(reloaded.activities.first?.isDone == true)
        #expect(reloaded.notes.first?.text == "Edited note")
        #expect(reloaded.links.first?.title == "Edited link")

        // DELETE: removing an item offline persists too.
        if let activity = reloaded.activities.first {
            context.delete(activity)
            try context.save()
        }
        let afterDelete = try #require(try context.fetch(FetchDescriptor<Trip>()).first)
        #expect(afterDelete.activities.count == 2)
    }

    // MARK: - Req 10.5 — flight lookup offline

    /// An offline flight lookup surfaces the clear offline message and leaves
    /// EVERY typed field exactly as the user entered it (not just airline/number),
    /// so nothing is lost and manual entry stays fully available.
    @Test func flightLookupOfflinePreservesEveryTypedField() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = FlightEditViewModel(
            mode: .create(trip),
            flightLookup: MockFlightLookupService(errorToThrow: .offline)
        )

        // The user has typed a full manual entry before trying a lookup. Keep
        // arrival after departure in a single zone so the entry is genuinely
        // valid (and thus `canSave`), isolating the test to data preservation.
        vm.airline = "Typed Airline"
        vm.flightNumber = "XX123"
        vm.departureAirport = SampleData.heathrow
        vm.arrivalAirport = SampleData.haneda
        vm.departureZoneIdentifier = "Europe/London"
        vm.arrivalZoneIdentifier = "Europe/London"
        vm.departureLocalTime = Date()
        vm.arrivalLocalTime = vm.departureLocalTime.addingTimeInterval(2 * 3600)
        vm.terminal = "T5"
        vm.gate = "G9"
        vm.bookingReference = "REF42"
        vm.seat = "12C"
        vm.notes = "Aisle, vegetarian meal"
        let departureBefore = vm.departureLocalTime
        let arrivalBefore = vm.arrivalLocalTime

        await vm.lookUp()

        // Distinct, clear offline state (not a crash, not a silent no-op).
        #expect(vm.lookupErrorMessage == FlightLookupError.offline.message)

        // Every field the user typed is byte-for-byte intact.
        #expect(vm.airline == "Typed Airline")
        #expect(vm.flightNumber == "XX123")
        #expect(vm.departureAirport?.name == SampleData.heathrow.name)
        #expect(vm.arrivalAirport?.name == SampleData.haneda.name)
        #expect(vm.departureZoneIdentifier == "Europe/London")
        #expect(vm.arrivalZoneIdentifier == "Europe/London")
        #expect(vm.terminal == "T5")
        #expect(vm.gate == "G9")
        #expect(vm.bookingReference == "REF42")
        #expect(vm.seat == "12C")
        #expect(vm.notes == "Aisle, vegetarian meal")
        #expect(vm.departureLocalTime == departureBefore)
        #expect(vm.arrivalLocalTime == arrivalBefore)

        // The form is still saveable — manual entry remains fully available.
        #expect(vm.canSave == true)
    }

    /// An offline flight lookup must not insert or delete any SwiftData model:
    /// nothing is persisted by a failed lookup (Req 10.5).
    @Test func flightLookupOfflineLeavesStoreUnchanged() async throws {
        let context = makeContext()
        let trip = SampleData.makeTokyoTrip()
        context.insert(trip)
        try context.save()

        let before = try modelCounts(in: context)

        let vm = FlightEditViewModel(
            mode: .create(trip),
            flightLookup: MockFlightLookupService(errorToThrow: .offline)
        )
        vm.flightNumber = "XX123"
        await vm.lookUp()

        let after = try modelCounts(in: context)
        #expect(after == before)
    }

    // MARK: - Req 10.5 — suggestions offline

    /// An offline suggestions request lands in the distinct `.error` state (not
    /// `.empty`) AND leaves the form inputs (area, interests, pace) unchanged,
    /// so the user can retry when back online without re-entering anything.
    @Test func suggestionsOfflineIsErrorAndPreservesForm() async {
        let vm = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(errorToThrow: .offline)
        )
        vm.toggle(.food)
        vm.toggle(.museums)
        vm.pace = .packed
        vm.timePreset = .fullDay
        let areaBefore = vm.area
        let interestsBefore = vm.interests
        let paceBefore = vm.pace
        let availableBefore = vm.resolvedAvailableTime

        await vm.requestSuggestions()

        // Distinct error state, not empty.
        guard case .error = vm.state else {
            Issue.record("Expected .error, got \(vm.state)")
            return
        }
        #expect(vm.state != .empty)
        #expect(vm.errorMessage == SuggestionError.offline.message)

        // Form inputs are untouched.
        #expect(vm.area?.name == areaBefore?.name)
        #expect(vm.interests == interestsBefore)
        #expect(vm.pace == paceBefore)
        #expect(vm.resolvedAvailableTime == availableBefore)
    }

    /// An offline suggestions request persists nothing: no activity (or any
    /// other model) is created by a failed request (Req 10.5).
    @Test func suggestionsOfflineLeavesStoreUnchanged() async throws {
        let context = makeContext()
        let trip = SampleData.makeTokyoTrip()
        context.insert(trip)
        try context.save()

        let before = try modelCounts(in: context)

        let vm = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(errorToThrow: .offline)
        )
        await vm.requestSuggestions()

        let after = try modelCounts(in: context)
        #expect(after == before)
        #expect(vm.addedSuggestionIDs.isEmpty)
    }

    // MARK: - Req 10.5 — routing/directions offline

    /// With an offline routing service every travel leg resolves to
    /// `.unavailable`, and the day's timeline still renders every item — no
    /// entry is dropped and nothing throws out of day assembly (Req 4.6, 10.5).
    @Test func routingOfflineLeavesEveryLegUnavailableAndEntriesComplete() async {
        let trip = SampleData.makeTokyoTrip()
        let vm = DayItineraryViewModel(
            trip: trip,
            routing: MockRoutingService(errorToThrow: .offline)
        )

        // Select the activities day (several placed stops → several legs).
        if let activityDay = vm.dayStarts.first(where: { day in
            !vm.entries(forDayStarting: day).compactMap(vm.activity(for:)).isEmpty
        }) {
            vm.selectedDayStart = activityDay
        }

        // Snapshot the entries before resolving estimates.
        let entriesBefore = vm.entriesForSelectedDay.map(\.id)
        #expect(!entriesBefore.isEmpty)

        await vm.loadTravelEstimates()

        // Every leg degraded to .unavailable rather than throwing.
        let legs = vm.travelLegsForSelectedDay
        #expect(!legs.isEmpty)
        for leg in legs {
            #expect(vm.state(for: leg) == .unavailable)
        }

        // The timeline is unchanged and complete — no item was dropped because
        // routing was offline (graceful degrade, no data loss).
        let entriesAfter = vm.entriesForSelectedDay.map(\.id)
        #expect(entriesAfter == entriesBefore)
    }

    /// Resolving travel estimates offline must not insert or delete any
    /// SwiftData model: the day view is read-only over the saved graph (Req 10.5).
    @Test func routingOfflineLeavesStoreUnchanged() async throws {
        let context = makeContext()
        let trip = SampleData.makeTokyoTrip()
        context.insert(trip)
        try context.save()

        let before = try modelCounts(in: context)

        let vm = DayItineraryViewModel(
            trip: trip,
            routing: MockRoutingService(errorToThrow: .offline)
        )
        if let activityDay = vm.dayStarts.first(where: { day in
            !vm.entries(forDayStarting: day).compactMap(vm.activity(for:)).isEmpty
        }) {
            vm.selectedDayStart = activityDay
        }
        await vm.loadTravelEstimates()

        let after = try modelCounts(in: context)
        #expect(after == before)
    }
}
