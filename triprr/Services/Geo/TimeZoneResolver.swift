//
//  TimeZoneResolver.swift
//  triprr
//
//  Resolves an IANA time zone for a coordinate via reverse geocoding, so that
//  places saved from search carry the correct zone for local-time display.
//  Not networked beyond geocoding; failures fall back gracefully so saves are
//  never blocked (Req 10.2, 10.3, 10.5).
//

import Foundation
import CoreLocation
import MapKit

/// Resolves time zones for places/coordinates.
nonisolated protocol TimeZoneResolving: Sendable {
    /// Returns an IANA time-zone identifier for the coordinate, or nil if it
    /// can't be resolved (e.g. offline).
    func timeZoneIdentifier(for coordinate: CLLocationCoordinate2D) async -> String?
}

/// `MKReverseGeocodingRequest`-backed resolver with a graceful offline
/// fallback (MapKit 26 replacement for the deprecated `CLGeocoder`).
nonisolated struct TimeZoneResolver: TimeZoneResolving {
    func timeZoneIdentifier(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            return mapItems.first?.timeZone?.identifier
        } catch {
            // Offline or geocoding failure: caller keeps whatever zone it had.
            return nil
        }
    }
}

nonisolated extension TimeZoneResolving {
    /// Returns a copy of `place` with its time zone resolved if it was missing.
    /// If resolution fails, the place is returned unchanged.
    func resolvingTimeZone(for place: Place) async -> Place {
        guard place.timeZoneIdentifier == nil else { return place }
        guard let identifier = await timeZoneIdentifier(for: place.coordinate) else {
            return place
        }
        var copy = place
        copy.timeZoneIdentifier = identifier
        return copy
    }
}

/// A mock resolver for previews/tests that returns a fixed identifier.
nonisolated struct MockTimeZoneResolver: TimeZoneResolving {
    var identifier: String?
    init(identifier: String? = "Europe/London") { self.identifier = identifier }
    func timeZoneIdentifier(for coordinate: CLLocationCoordinate2D) async -> String? {
        identifier
    }
}
