//
//  Booking.swift
//  triprr
//
//  An "other booking": restaurant reservation, tour, ticket, transport, etc.
//

import Foundation
import SwiftData

@Model
final class Booking {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = BookingKind.other.rawValue
    var place: Place?
    /// Stored in UTC; displayed in `effectiveTimeZone`.
    var startDate: Date = Date()
    /// Optional end of a time range.
    var endDate: Date?
    var timeZoneIdentifier: String?
    var confirmationNumber: String?
    var notes: String?
    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String = "",
        kind: BookingKind = .other,
        place: Place? = nil,
        startDate: Date,
        endDate: Date? = nil,
        timeZoneIdentifier: String? = nil,
        confirmationNumber: String? = nil,
        notes: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.place = place
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.confirmationNumber = confirmationNumber
        self.notes = notes
        self.trip = trip
    }
}

extension Booking {
    var kind: BookingKind {
        get { BookingKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var effectiveTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? place?.timeZone
            ?? trip?.primaryTimeZone
            ?? .current
    }
}
