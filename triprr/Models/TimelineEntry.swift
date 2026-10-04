//
//  TimelineEntry.swift
//  triprr
//
//  A value type that unifies flights, stays, bookings and activities into one
//  ordered list for day views, the trip timeline and the Today screen, without
//  a shared model superclass. Each entry exposes a common interface (title,
//  start/end instants, zone, place, symbol, source reference).
//

import Foundation
import SwiftData

/// Identifies the originating model and sub-aspect of a timeline entry.
nonisolated enum TimelineSource: Hashable, Sendable {
    case flight(flightID: UUID)
    case stayCheckIn(stayID: UUID)
    case stayCheckOut(stayID: UUID)
    case booking(bookingID: UUID)
    case activity(activityID: UUID)
}

/// A single item on a day's timeline.
nonisolated struct TimelineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let source: TimelineSource
    let title: String
    let subtitle: String?
    /// Stored in UTC.
    let start: Date
    /// Stored in UTC; nil for point-in-time entries.
    let end: Date?
    let timeZoneIdentifier: String?
    let place: Place?
    let symbolName: String
    /// Lower sorts earlier among entries sharing the same `start`.
    let sortOrder: Int
    let isDone: Bool

    var timeZone: TimeZone {
        TimeZone.resolved(timeZoneIdentifier)
    }

    /// Whether this entry originates from a flight, used by the schedule
    /// evaluator to apply the airport lead buffer before a flight (Req 4.5).
    var isFlight: Bool {
        if case .flight = source { return true }
        return false
    }
}

// MARK: - Building entries from models

extension Flight {
    /// A flight appears on the timeline at its departure instant.
    @MainActor
    var timelineEntry: TimelineEntry {
        TimelineEntry(
            id: id,
            source: .flight(flightID: id),
            title: "\(airline) \(flightNumber)".trimmingCharacters(in: .whitespaces),
            subtitle: "\(departureAirport.name) → \(arrivalAirport.name)",
            start: scheduledDeparture,
            end: scheduledArrival,
            timeZoneIdentifier: departureAirport.timeZoneIdentifier,
            place: departureAirport,
            symbolName: "airplane",
            sortOrder: -100, // flights lead their day
            isDone: false
        )
    }
}

extension Stay {
    @MainActor
    var checkInEntry: TimelineEntry {
        TimelineEntry(
            id: id,
            source: .stayCheckIn(stayID: id),
            title: "Check in: \(name)",
            subtitle: place?.name,
            start: checkIn,
            end: nil,
            timeZoneIdentifier: effectiveTimeZone.identifier,
            place: place,
            symbolName: kind.symbolName,
            sortOrder: -50,
            isDone: false
        )
    }

    @MainActor
    var checkOutEntry: TimelineEntry {
        // Distinct id from the check-in entry (both derive from one stay).
        let outID = UUID(uuidString: id.uuidString) ?? id
        return TimelineEntry(
            id: deterministicChildID(of: outID, salt: 1),
            source: .stayCheckOut(stayID: id),
            title: "Check out: \(name)",
            subtitle: place?.name,
            start: checkOut,
            end: nil,
            timeZoneIdentifier: effectiveTimeZone.identifier,
            place: place,
            symbolName: kind.symbolName,
            sortOrder: -40,
            isDone: false
        )
    }
}

extension Booking {
    @MainActor
    var timelineEntry: TimelineEntry {
        TimelineEntry(
            id: id,
            source: .booking(bookingID: id),
            title: title,
            subtitle: place?.name,
            start: startDate,
            end: endDate,
            timeZoneIdentifier: effectiveTimeZone.identifier,
            place: place,
            symbolName: kind.symbolName,
            sortOrder: 0,
            isDone: false
        )
    }
}

extension Activity {
    @MainActor
    var timelineEntry: TimelineEntry {
        TimelineEntry(
            id: id,
            source: .activity(activityID: id),
            title: title,
            subtitle: place?.name,
            start: startDate,
            end: endDate,
            timeZoneIdentifier: effectiveTimeZone.identifier,
            place: place,
            symbolName: category.symbolName,
            sortOrder: sortOrder,
            isDone: isDone
        )
    }
}

// MARK: - Ordering

nonisolated extension Array where Element == TimelineEntry {
    /// Entries sorted by start instant, then by sortOrder, then title.
    func chronological() -> [TimelineEntry] {
        sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.title < rhs.title
        }
    }
}

/// Produces a stable child UUID from a parent UUID and a small salt, so a stay
/// can emit two distinct-but-deterministic timeline entry ids.
private nonisolated func deterministicChildID(of parent: UUID, salt: UInt8) -> UUID {
    var bytes = parent.uuid
    bytes.15 = bytes.15 ^ salt
    return UUID(uuid: bytes)
}
