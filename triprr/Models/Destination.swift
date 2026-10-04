//
//  Destination.swift
//  triprr
//
//  A place the trip goes to. Drives the dashboard map and the trip's primary
//  time zone.
//

import Foundation
import SwiftData

@Model
final class Destination {
    var id: UUID = UUID()
    var place: Place = Place(name: "", latitude: 0, longitude: 0)
    var sortOrder: Int = 0
    var trip: Trip?

    init(
        id: UUID = UUID(),
        place: Place,
        sortOrder: Int = 0,
        trip: Trip? = nil
    ) {
        self.id = id
        self.place = place
        self.sortOrder = sortOrder
        self.trip = trip
    }
}
