//
//  Trip.swift
//  triprr
//
//  The root entity. A trip owns its destinations, flights, stays, bookings,
//  activities, notes and links; deleting a trip cascades to all of them.
//

import Foundation
import SwiftData

@Model
final class Trip {
    var id: UUID = UUID()
    var name: String = ""
    /// Stored in UTC. Trip day boundaries are computed in `primaryTimeZone`.
    var startDate: Date = Date()
    var endDate: Date = Date()
    /// Optional colour cover, stored as a hex string (e.g. "#FF8800").
    var coverColorHex: String?
    /// Optional image cover, kept out of the main store.
    @Attribute(.externalStorage) var coverImageData: Data?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Destination.trip)
    var destinations: [Destination] = []
    @Relationship(deleteRule: .cascade, inverse: \Flight.trip)
    var flights: [Flight] = []
    @Relationship(deleteRule: .cascade, inverse: \Stay.trip)
    var stays: [Stay] = []
    @Relationship(deleteRule: .cascade, inverse: \Booking.trip)
    var bookings: [Booking] = []
    @Relationship(deleteRule: .cascade, inverse: \Activity.trip)
    var activities: [Activity] = []
    @Relationship(deleteRule: .cascade, inverse: \Note.trip)
    var notes: [Note] = []
    @Relationship(deleteRule: .cascade, inverse: \LinkItem.trip)
    var links: [LinkItem] = []

    init(
        id: UUID = UUID(),
        name: String = "",
        startDate: Date = Date(),
        endDate: Date = Date(),
        coverColorHex: String? = nil,
        coverImageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.coverColorHex = coverColorHex
        self.coverImageData = coverImageData
        self.createdAt = createdAt
    }
}

extension Trip {
    /// The trip's primary time zone: the first destination's resolved zone,
    /// falling back to the device's current zone.
    var primaryTimeZone: TimeZone {
        destinations
            .sorted { $0.sortOrder < $1.sortOrder }
            .lazy
            .compactMap { $0.place.timeZone }
            .first ?? .current
    }

    /// Trip status relative to `now`, evaluated in the trip's primary zone.
    func status(now: Date = Date()) -> TripStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = primaryTimeZone
        let startDay = calendar.startOfDay(for: startDate)
        // The trip is current through the end of its last day.
        let endDay = calendar.startOfDay(for: endDate)
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate

        if now < startDay {
            return .upcoming
        } else if now >= dayAfterEnd {
            return .past
        } else {
            return .current
        }
    }

    /// All placed locations across the trip, for the dashboard map.
    var allPlaces: [Place] {
        var places: [Place] = destinations.map(\.place)
        places += flights.flatMap { [$0.departureAirport, $0.arrivalAirport] }
        places += stays.compactMap(\.place)
        places += bookings.compactMap(\.place)
        places += activities.compactMap(\.place)
        return places
    }
}
