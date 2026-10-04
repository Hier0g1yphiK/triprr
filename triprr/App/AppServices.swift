//
//  AppServices.swift
//  triprr
//
//  Dependency container for the app's services. Concrete implementations are
//  injected here and passed through the SwiftUI environment so that previews
//  and tests can substitute mocks without touching the views.
//

import SwiftUI

/// Container for the app's service layer.
///
/// Services are defined as protocols elsewhere in the `Services` layer; this
/// type holds the concrete instances the running app uses. It is passed through
/// the SwiftUI environment via ``EnvironmentValues/appServices``.
///
/// As services are added in later tasks (flight lookup, suggestions, routing,
/// place search, notifications), they are stored here. For now it is an empty
/// container that establishes the injection seam.
@MainActor
struct AppServices {
    var placeSearch: any PlaceSearchService
    var timeZoneResolver: any TimeZoneResolving
    var flightLookup: any FlightLookupService
    var routing: any RoutingService
    var suggestions: any SuggestionService
    var notifications: any NotificationScheduling

    init(
        placeSearch: any PlaceSearchService = MapKitPlaceSearchService(),
        timeZoneResolver: any TimeZoneResolving = TimeZoneResolver(),
        flightLookup: any FlightLookupService = MockFlightLookupService(),
        routing: any RoutingService = MapKitRoutingService(),
        suggestions: any SuggestionService = MapKitSuggestionService(),
        notifications: any NotificationScheduling = LocalNotificationScheduler()
    ) {
        self.placeSearch = placeSearch
        self.timeZoneResolver = timeZoneResolver
        self.flightLookup = flightLookup
        self.routing = routing
        self.suggestions = suggestions
        self.notifications = notifications
    }

    /// The services used by the running app.
    ///
    /// Flight lookup ships with `MockFlightLookupService` for now; a real
    /// API-backed provider plugs in behind `FlightLookupService` later without
    /// any UI change (Req 2.4). Suggestions use the MapKit-backed
    /// `MapKitSuggestionService` (`MKLocalSearch` discovery); the UI depends
    /// only on the `SuggestionService` protocol so the provider can still change
    /// freely.
    static let live = AppServices()

    /// A preview/test container backed by mocks (no network).
    static let mock = AppServices(
        placeSearch: MockPlaceSearchService(),
        timeZoneResolver: MockTimeZoneResolver(),
        flightLookup: MockFlightLookupService(),
        routing: MockRoutingService(),
        suggestions: MockSuggestionService(),
        notifications: NoopNotificationScheduler()
    )
}

// MARK: - Environment

private struct AppServicesKey: EnvironmentKey {
    static let defaultValue = AppServices.live
}

extension EnvironmentValues {
    /// The app's service container, injected at the root and read by view models.
    var appServices: AppServices {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
