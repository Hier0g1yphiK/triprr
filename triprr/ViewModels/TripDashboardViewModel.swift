//
//  TripDashboardViewModel.swift
//  triprr
//
//  Backs the trip dashboard: status/countdown and the map region covering the
//  trip's places. Section shortcuts (Flights/Stays/Itinerary/Suggestions) are
//  presented by the view; their destinations are filled in by later tasks.
//

import Foundation
import SwiftUI
import MapKit

@MainActor
@Observable
final class TripDashboardViewModel {
    /// The countdown/status for a trip in its primary zone.
    func countdown(for trip: Trip, now: Date = Date()) -> TripCountdown {
        TripCountdown.make(
            start: trip.startDate,
            end: trip.endDate,
            timeZone: trip.primaryTimeZone,
            now: now
        )
    }

    /// A map camera position framing all of the trip's places, or nil if the
    /// trip has none yet.
    func mapPosition(for trip: Trip) -> MapCameraPosition? {
        let coordinates = trip.allPlaces.map(\.coordinate)
        guard !coordinates.isEmpty else { return nil }

        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Pad the span so pins aren't on the edge.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Distinct, named places for map annotations.
    func annotatedPlaces(for trip: Trip) -> [Place] {
        var seen = Set<String>()
        var result: [Place] = []
        for place in trip.allPlaces {
            let key = "\(place.latitude),\(place.longitude)"
            if seen.insert(key).inserted {
                result.append(place)
            }
        }
        return result
    }
}
