//
//  RoutingService.swift
//  triprr
//
//  Protocol + MapKit implementation for estimating travel time and distance
//  between two places (Req 4.4). The day itinerary shows a compact per-leg
//  estimate between consecutive placed items; when directions can't be computed
//  (offline, no route, missing place) the UI degrades gracefully rather than
//  failing the day view (Req 4.6). Behind a protocol so previews/tests
//  substitute a deterministic mock and a different provider could be swapped in
//  later without changing the UI.
//

import Foundation
import CoreLocation
import MapKit

/// A single leg to estimate: travel from one place to another by a mode.
nonisolated struct RouteLeg: Hashable, Sendable {
    var origin: Place
    var destination: Place
    var mode: TravelMode

    init(origin: Place, destination: Place, mode: TravelMode) {
        self.origin = origin
        self.destination = destination
        self.mode = mode
    }
}

/// The estimated time and distance for a leg.
nonisolated struct RouteEstimate: Hashable, Sendable {
    /// Estimated travel time, in seconds.
    let travelTime: TimeInterval
    /// Estimated travel distance, in meters.
    let distance: CLLocationDistance
    /// The mode the estimate was computed for.
    let mode: TravelMode

    init(travelTime: TimeInterval, distance: CLLocationDistance, mode: TravelMode) {
        self.travelTime = travelTime
        self.distance = distance
        self.mode = mode
    }
}

/// Errors a routing estimate can surface. The day view catches these and
/// degrades gracefully (Req 4.6).
nonisolated enum RoutingError: Error, Equatable {
    /// No network connection.
    case offline
    /// No route exists between the two places (e.g. across an ocean by car).
    case noRoute
    /// Routing is unavailable for this request (e.g. transit not supported).
    case unavailable
    /// The estimate failed for another reason.
    case failed
}

/// Estimates travel time and distance between two places.
///
/// Networked implementations throw `RoutingError`; the UI depends only on this
/// protocol so the concrete provider can change freely.
nonisolated protocol RoutingService: Sendable {
    func estimate(from origin: Place, to destination: Place, mode: TravelMode) async throws -> RouteEstimate
}

nonisolated extension RoutingService {
    /// Convenience that estimates a `RouteLeg`.
    func estimate(_ leg: RouteLeg) async throws -> RouteEstimate {
        try await estimate(from: leg.origin, to: leg.destination, mode: leg.mode)
    }
}

// MARK: - Formatting

nonisolated extension RouteEstimate {
    /// A compact, user-facing label such as "15 min · 3.2 km · Driving".
    var compactLabel: String {
        "\(timeLabel) · \(distanceLabel) · \(mode.displayName)"
    }

    /// The travel time as a short string, e.g. "15 min" or "1 hr 20 min".
    var timeLabel: String {
        let totalMinutes = max(1, Int((travelTime / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }

    /// The distance as a short, locale-aware string, e.g. "3.2 km".
    var distanceLabel: String {
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(0...1))
            )
        )
    }
}

// MARK: - MapKit implementation

/// `MKDirections`-backed routing with a concurrency-safe in-memory cache.
///
/// Estimates are cached by (origin coord, destination coord, mode) so switching
/// days or redrawing a row doesn't recompute a leg. The cache is an `actor`,
/// which keeps the service `Sendable` while serialising access.
nonisolated struct MapKitRoutingService: RoutingService {
    private let cache = RouteEstimateCache()

    init() {}

    func estimate(from origin: Place, to destination: Place, mode: TravelMode) async throws -> RouteEstimate {
        let key = RouteCacheKey(origin: origin, destination: destination, mode: mode)
        if let cached = await cache.estimate(for: key) {
            return cached
        }

        let estimate = try await calculate(from: origin, to: destination, mode: mode)
        await cache.store(estimate, for: key)
        return estimate
    }

    /// Bridges `MKDirections.calculate(completionHandler:)` to async and maps
    /// the fastest route to a `RouteEstimate`.
    private func calculate(from origin: Place, to destination: Place, mode: TravelMode) async throws -> RouteEstimate {
        let request = MKDirections.Request()
        request.source = origin.mapItem
        request.destination = destination.mapItem
        request.transportType = mode.directionsTransportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let fastest = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                throw RoutingError.noRoute
            }
            return RouteEstimate(
                travelTime: fastest.expectedTravelTime,
                distance: fastest.distance,
                mode: mode
            )
        } catch let error as RoutingError {
            throw error
        } catch {
            throw Self.mapError(error)
        }
    }

    /// Maps an `MKDirections` failure to a typed `RoutingError`.
    private static func mapError(_ error: Error) -> RoutingError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .offline
        }
        if let mkError = error as? MKError {
            switch mkError.code {
            case .directionsNotFound, .placemarkNotFound:
                return .noRoute
            case .loadingThrottled, .serverFailure:
                return .failed
            default:
                return .unavailable
            }
        }
        return .failed
    }
}

/// A key for caching a leg estimate. Coordinates are quantised to a small grid
/// so near-identical requests reuse the same cached value.
private nonisolated struct RouteCacheKey: Hashable, Sendable {
    let originLat: Int
    let originLon: Int
    let destLat: Int
    let destLon: Int
    let mode: TravelMode

    init(origin: Place, destination: Place, mode: TravelMode) {
        // ~1e-5 degrees ≈ 1 m; quantising avoids float-equality misses while
        // keeping distinct places distinct.
        func quantise(_ value: Double) -> Int { Int((value * 100_000).rounded()) }
        self.originLat = quantise(origin.latitude)
        self.originLon = quantise(origin.longitude)
        self.destLat = quantise(destination.latitude)
        self.destLon = quantise(destination.longitude)
        self.mode = mode
    }
}

/// A concurrency-safe store of leg estimates. An `actor` so the `Sendable`
/// routing service can mutate it from any task without data races.
private actor RouteEstimateCache {
    private var storage: [RouteCacheKey: RouteEstimate] = [:]

    func estimate(for key: RouteCacheKey) -> RouteEstimate? {
        storage[key]
    }

    func store(_ estimate: RouteEstimate, for key: RouteCacheKey) {
        storage[key] = estimate
    }
}

// MARK: - TravelMode bridging

nonisolated extension TravelMode {
    /// The `MKDirectionsTransportType` for this mode.
    var directionsTransportType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .walking: .walking
        case .transit: .transit
        }
    }
}

// MARK: - Mock

/// A deterministic mock for the running-app fallback, previews and tests.
///
/// Produces an estimate from the great-circle distance between the two places
/// and a per-mode average speed, so previews and tests show plausible,
/// repeatable legs without touching the network. Can be configured to throw to
/// exercise the graceful-degrade path (Req 4.6).
nonisolated struct MockRoutingService: RoutingService {
    /// When set, every estimate throws this error.
    var errorToThrow: RoutingError?
    /// Simulated latency so previews/tests can observe a loading state.
    var delay: Duration

    init(errorToThrow: RoutingError? = nil, delay: Duration = .zero) {
        self.errorToThrow = errorToThrow
        self.delay = delay
    }

    func estimate(from origin: Place, to destination: Place, mode: TravelMode) async throws -> RouteEstimate {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let errorToThrow { throw errorToThrow }

        let straightLine = origin.location.distance(from: destination.location)
        // Roads/paths aren't straight: pad the great-circle distance a little.
        let distance = straightLine * 1.3
        let travelTime = distance / Self.metersPerSecond(for: mode)
        return RouteEstimate(
            travelTime: travelTime,
            distance: distance,
            mode: mode
        )
    }

    /// A representative average speed (m/s) per mode for synthesising a time.
    private static func metersPerSecond(for mode: TravelMode) -> Double {
        switch mode {
        case .automobile: 11.0   // ~40 km/h in-city
        case .walking: 1.4       // ~5 km/h
        case .transit: 8.3       // ~30 km/h door-to-door
        }
    }
}
