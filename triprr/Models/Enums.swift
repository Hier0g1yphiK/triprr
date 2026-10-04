//
//  Enums.swift
//  triprr
//
//  Shared value-type enumerations used across the models, services and views.
//  Each carries a display name and an SF Symbol for consistent presentation.
//

import Foundation

/// Where a trip sits relative to the current date.
nonisolated enum TripStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case current
    case past

    var displayName: String {
        switch self {
        case .upcoming: "Upcoming"
        case .current: "Current"
        case .past: "Past"
        }
    }

    var symbolName: String {
        switch self {
        case .upcoming: "calendar"
        case .current: "airplane.departure"
        case .past: "checkmark.circle"
        }
    }
}

/// The kind of a stay (lodging).
nonisolated enum StayKind: String, Codable, CaseIterable, Sendable {
    case hotel
    case rental

    var displayName: String {
        switch self {
        case .hotel: "Hotel"
        case .rental: "Rental"
        }
    }

    var symbolName: String {
        switch self {
        case .hotel: "bed.double"
        case .rental: "house"
        }
    }
}

/// The kind of an "other booking".
nonisolated enum BookingKind: String, Codable, CaseIterable, Sendable {
    case restaurant
    case tour
    case ticket
    case transport
    case other

    var displayName: String {
        switch self {
        case .restaurant: "Restaurant"
        case .tour: "Tour"
        case .ticket: "Ticket"
        case .transport: "Transport"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .restaurant: "fork.knife"
        case .tour: "figure.walk"
        case .ticket: "ticket"
        case .transport: "tram"
        case .other: "mappin.and.ellipse"
        }
    }
}

/// The category of an itinerary activity. Also used to map suggestions and to
/// estimate per-category visit durations.
nonisolated enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case food
    case museum
    case outdoors
    case nightlife
    case shopping
    case landmark
    case transport
    case other

    var displayName: String {
        switch self {
        case .food: "Food"
        case .museum: "Museum"
        case .outdoors: "Outdoors"
        case .nightlife: "Nightlife"
        case .shopping: "Shopping"
        case .landmark: "Landmark"
        case .transport: "Transport"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .museum: "building.columns"
        case .outdoors: "leaf"
        case .nightlife: "moon.stars"
        case .shopping: "bag"
        case .landmark: "mappin.and.ellipse"
        case .transport: "tram"
        case .other: "star"
        }
    }
}

/// Travel mode for routing and travel-time estimates.
nonisolated enum TravelMode: String, Codable, CaseIterable, Sendable {
    case automobile
    case walking
    case transit

    var displayName: String {
        switch self {
        case .automobile: "Driving"
        case .walking: "Walking"
        case .transit: "Transit"
        }
    }

    var symbolName: String {
        switch self {
        case .automobile: "car"
        case .walking: "figure.walk"
        case .transit: "tram"
        }
    }
}

/// How densely the user wants a suggested day planned.
nonisolated enum Pace: String, Codable, CaseIterable, Sendable {
    case relaxed
    case packed

    var displayName: String {
        switch self {
        case .relaxed: "Relaxed"
        case .packed: "Packed"
        }
    }

    var symbolName: String {
        switch self {
        case .relaxed: "tortoise"
        case .packed: "hare"
        }
    }

    /// Multiplier applied to a category's base visit duration. Packed days
    /// spend less time per stop; relaxed days spend more.
    var durationMultiplier: Double {
        switch self {
        case .relaxed: 1.25
        case .packed: 0.8
        }
    }
}

/// A user interest used to seed suggestion searches.
nonisolated enum Interest: String, Codable, CaseIterable, Sendable {
    case food
    case museums
    case outdoors
    case nightlife
    case shopping
    case landmarks

    var displayName: String {
        switch self {
        case .food: "Food"
        case .museums: "Museums"
        case .outdoors: "Outdoors"
        case .nightlife: "Nightlife"
        case .shopping: "Shopping"
        case .landmarks: "Landmarks"
        }
    }

    var symbolName: String {
        switch self {
        case .food: "fork.knife"
        case .museums: "building.columns"
        case .outdoors: "leaf"
        case .nightlife: "moon.stars"
        case .shopping: "bag"
        case .landmarks: "mappin.and.ellipse"
        }
    }

    /// The activity category a suggestion in this interest maps to.
    var activityCategory: ActivityCategory {
        switch self {
        case .food: .food
        case .museums: .museum
        case .outdoors: .outdoors
        case .nightlife: .nightlife
        case .shopping: .shopping
        case .landmarks: .landmark
        }
    }
}
