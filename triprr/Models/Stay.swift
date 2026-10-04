//
//  Stay.swift
//  triprr
//
//  A hotel or rental with check-in and check-out instants.
//

import Foundation
import SwiftData

@Model
final class Stay {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = StayKind.hotel.rawValue
    var place: Place?
    /// Stored in UTC; displayed in `effectiveTimeZone`.
    var checkIn: Date = Date()
    var checkOut: Date = Date()
    var timeZoneIdentifier: String?
    var confirmationNumber: String?
    var notes: String?
    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String = "",
        kind: StayKind = .hotel,
        place: Place? = nil,
        checkIn: Date,
        checkOut: Date,
        timeZoneIdentifier: String? = nil,
        confirmationNumber: String? = nil,
        notes: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.place = place
        self.checkIn = checkIn
        self.checkOut = checkOut
        self.timeZoneIdentifier = timeZoneIdentifier
        self.confirmationNumber = confirmationNumber
        self.notes = notes
        self.trip = trip
    }
}

extension Stay {
    var kind: StayKind {
        get { StayKind(rawValue: kindRaw) ?? .hotel }
        set { kindRaw = newValue.rawValue }
    }

    /// The zone to display check-in/out in: the stay's own, the place's, the
    /// trip's primary, then the device zone.
    var effectiveTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? place?.timeZone
            ?? trip?.primaryTimeZone
            ?? .current
    }
}
