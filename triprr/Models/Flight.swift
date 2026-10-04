//
//  Flight.swift
//  triprr
//
//  A flight leg. Each airport carries its own time zone via its Place, so
//  departure and arrival are displayed in the correct local time.
//

import Foundation
import SwiftData

@Model
final class Flight {
    var id: UUID = UUID()
    var airline: String = ""
    var flightNumber: String = ""
    var departureAirport: Place = Place(name: "", latitude: 0, longitude: 0)
    var arrivalAirport: Place = Place(name: "", latitude: 0, longitude: 0)
    /// Stored in UTC; displayed in `departureAirport.timeZone`.
    var scheduledDeparture: Date = Date()
    /// Stored in UTC; displayed in `arrivalAirport.timeZone`.
    var scheduledArrival: Date = Date()
    var terminal: String?
    var gate: String?
    var bookingReference: String?
    var seat: String?
    var notes: String?
    var trip: Trip?

    init(
        id: UUID = UUID(),
        airline: String = "",
        flightNumber: String = "",
        departureAirport: Place,
        arrivalAirport: Place,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        terminal: String? = nil,
        gate: String? = nil,
        bookingReference: String? = nil,
        seat: String? = nil,
        notes: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.airline = airline
        self.flightNumber = flightNumber
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.terminal = terminal
        self.gate = gate
        self.bookingReference = bookingReference
        self.seat = seat
        self.notes = notes
        self.trip = trip
    }
}

extension Flight {
    /// The time zone to display departure in.
    var departureTimeZone: TimeZone {
        departureAirport.timeZone ?? trip?.primaryTimeZone ?? .current
    }

    /// The time zone to display arrival in.
    var arrivalTimeZone: TimeZone {
        arrivalAirport.timeZone ?? trip?.primaryTimeZone ?? .current
    }
}
