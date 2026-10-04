//
//  Place.swift
//  triprr
//
//  A saved location derived from a MapKit MKMapItem. Stored as a Codable value
//  type (not a SwiftData entity) on the entities that have a location, which
//  keeps the model graph simple and avoids cross-trip aliasing for the MVP.
//

import Foundation
import CoreLocation
import MapKit

/// A location with a name, coordinate, optional address and resolved time zone.
///
/// Coordinates are stored as plain `Double`s so the value is trivially
/// `Codable`. The IANA `timeZoneIdentifier` is filled in by `TimeZoneResolver`
/// when a place is saved; where local time matters (airports, activities), it
/// drives display in the correct zone.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    /// IANA identifier (e.g. "Europe/London"). Nil until resolved.
    var timeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated extension Place {
    /// The geographic coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// The resolved time zone, if an identifier is stored and valid.
    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// A `CLLocation` for distance math.
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

// MARK: - MapKit bridging

nonisolated extension Place {
    /// Builds a `Place` from a MapKit map item (MapKit 26 API).
    init(mapItem: MKMapItem) {
        let coordinate = mapItem.location.coordinate
        let formatted = mapItem.addressRepresentations?
            .fullAddress(includingRegion: true, singleLine: true)
            ?? mapItem.address?.fullAddress
        self.init(
            name: mapItem.name ?? formatted ?? "Unknown place",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: formatted,
            timeZoneIdentifier: mapItem.timeZone?.identifier
        )
    }

    /// A map item for opening in Maps or computing directions.
    var mapItem: MKMapItem {
        let mkAddress = address.flatMap { MKAddress(fullAddress: $0, shortAddress: nil) }
        let item = MKMapItem(location: location, address: mkAddress)
        item.name = name
        return item
    }
}
