//
//  StayBookingPersistenceTests.swift
//  triprrTests
//
//  Round-trips a Stay and a Booking through an in-memory ModelContainer to
//  prove create / edit / delete persist via SwiftData and are reflected on a
//  fresh fetch (Req 3.5). These mirror the save paths used by StayEditView,
//  BookingEditView, StaysListView and BookingsListView.
//

import Testing
import Foundation
import SwiftData
@testable import triprr

@MainActor
struct StayBookingPersistenceTests {

    /// A fresh, empty in-memory container owned by the test instance.
    ///
    /// The container must be retained for the lifetime of the test: a
    /// `ModelContext` does not keep its `ModelContainer` alive, so handing back
    /// only `container.mainContext` would let the container (and its backing
    /// store) deallocate out from under us, crashing the next insert/save.
    private let container = SampleData.emptyContainer()

    private func makeContext() -> ModelContext {
        container.mainContext
    }

    /// Inserts and saves a trip to own the stay/booking under test.
    private func makeTrip(in context: ModelContext) -> Trip {
        let trip = Trip(
            name: "Persistence Trip",
            startDate: Date(),
            endDate: Date().addingTimeInterval(5 * 86_400)
        )
        context.insert(trip)
        try? context.save()
        return trip
    }

    // MARK: - Stay

    @Test func stayCreateEditDeleteRoundTrips() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)

        let checkIn = Date()
        let checkOut = checkIn.addingTimeInterval(2 * 86_400)

        // CREATE — mirrors StayEditView.save() create branch.
        let stay = Stay(
            name: "Hotel Alpha",
            kind: .hotel,
            place: SampleData.tokyoStation,
            checkIn: checkIn,
            checkOut: checkOut,
            timeZoneIdentifier: "Asia/Tokyo",
            confirmationNumber: "ABC123",
            notes: "High floor",
            trip: trip
        )
        context.insert(stay)
        try context.save()

        // A fresh fetch sees the saved stay.
        var fetched = try context.fetch(FetchDescriptor<Stay>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Hotel Alpha")
        #expect(fetched.first?.kind == .hotel)
        #expect(fetched.first?.confirmationNumber == "ABC123")

        // EDIT — mirrors StayEditView.save() edit branch (mutate + save).
        let toEdit = try #require(fetched.first)
        toEdit.name = "Hotel Beta"
        toEdit.kind = .rental
        toEdit.confirmationNumber = "XYZ789"
        toEdit.checkOut = checkIn.addingTimeInterval(3 * 86_400)
        try context.save()

        fetched = try context.fetch(FetchDescriptor<Stay>())
        #expect(fetched.count == 1)
        let edited = try #require(fetched.first)
        #expect(edited.name == "Hotel Beta")
        #expect(edited.kind == .rental)
        #expect(edited.confirmationNumber == "XYZ789")
        #expect(abs(edited.checkOut.timeIntervalSince(checkIn.addingTimeInterval(3 * 86_400))) < 1)

        // DELETE — mirrors StaysListView.delete().
        context.delete(edited)
        try context.save()

        fetched = try context.fetch(FetchDescriptor<Stay>())
        #expect(fetched.isEmpty)
    }

    // MARK: - Booking

    @Test func bookingCreateEditDeleteRoundTrips() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)

        let start = Date()

        // CREATE — mirrors BookingEditView.save() create branch (no end time).
        let booking = Booking(
            title: "Dinner Reservation",
            kind: .restaurant,
            place: SampleData.sushiRestaurant,
            startDate: start,
            endDate: nil,
            timeZoneIdentifier: "Asia/Tokyo",
            confirmationNumber: "RES-1",
            notes: "Table for two",
            trip: trip
        )
        context.insert(booking)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<Booking>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Dinner Reservation")
        #expect(fetched.first?.kind == .restaurant)
        #expect(fetched.first?.endDate == nil)

        // EDIT — add an end time (become a range) and change kind/title.
        let toEdit = try #require(fetched.first)
        toEdit.title = "Guided Tour"
        toEdit.kind = .tour
        let end = start.addingTimeInterval(2 * 3600)
        toEdit.endDate = end
        toEdit.confirmationNumber = "RES-2"
        try context.save()

        fetched = try context.fetch(FetchDescriptor<Booking>())
        #expect(fetched.count == 1)
        let edited = try #require(fetched.first)
        #expect(edited.title == "Guided Tour")
        #expect(edited.kind == .tour)
        #expect(edited.confirmationNumber == "RES-2")
        let editedEnd = try #require(edited.endDate)
        #expect(abs(editedEnd.timeIntervalSince(end)) < 1)

        // DELETE — mirrors BookingsListView.delete().
        context.delete(edited)
        try context.save()

        fetched = try context.fetch(FetchDescriptor<Booking>())
        #expect(fetched.isEmpty)
    }
}
