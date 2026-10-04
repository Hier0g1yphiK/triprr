//
//  PlaceSearchService.swift
//  triprr
//
//  Protocol + MapKit implementation for searching places. Powers the
//  PlaceSearchField used across trip destinations, activities, stays and
//  bookings. Behind a protocol so previews/tests substitute a mock and a real
//  provider could be swapped later without changing the UI.
//

import Foundation
import MapKit

/// Searches for places by free-text query, optionally scoped to a region.
nonisolated protocol PlaceSearchService: Sendable {
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place]
}

/// Errors a place search can surface.
nonisolated enum PlaceSearchError: Error, Equatable {
    case offline
    case failed
}

/// MapKit-backed implementation using `MKLocalSearch`.
nonisolated struct MapKitPlaceSearchService: PlaceSearchService {
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let region {
            request.region = region
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.map(Place.init(mapItem:))
        } catch let error as MKError where error.code == .loadingThrottled {
            throw PlaceSearchError.failed
        } catch {
            // MKLocalSearch surfaces network failures as generic errors; map
            // the common offline case so the UI can show the right state.
            if (error as NSError).domain == NSURLErrorDomain {
                throw PlaceSearchError.offline
            }
            throw PlaceSearchError.failed
        }
    }
}

/// A deterministic mock for previews and tests. Returns a small fixed set of
/// places derived from the query, never touching the network.
nonisolated struct MockPlaceSearchService: PlaceSearchService {
    var fixedResults: [Place]?
    var errorToThrow: PlaceSearchError?

    init(fixedResults: [Place]? = nil, errorToThrow: PlaceSearchError? = nil) {
        self.fixedResults = fixedResults
        self.errorToThrow = errorToThrow
    }

    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place] {
        if let errorToThrow { throw errorToThrow }
        if let fixedResults { return fixedResults }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [
            Place(name: "\(trimmed) City Center", latitude: 48.8566, longitude: 2.3522,
                  address: "\(trimmed), Example", timeZoneIdentifier: "Europe/Paris"),
            Place(name: "\(trimmed) Old Town", latitude: 48.8606, longitude: 2.3376,
                  address: "\(trimmed), Example", timeZoneIdentifier: "Europe/Paris"),
        ]
    }
}
