//
//  TripListViewModel.swift
//  triprr
//
//  Groups trips into Upcoming / Current / Past and sorts within each group.
//  Pure grouping logic lives here (and is simple enough to be exercised by the
//  list previews) while fetching stays with SwiftData @Query in the view.
//

import Foundation

/// A grouped section of trips for the list.
struct TripSection: Identifiable {
    let status: TripStatus
    let trips: [Trip]
    var id: TripStatus { status }
    var title: String { status.displayName }
    var symbolName: String { status.symbolName }
}

@MainActor
@Observable
final class TripListViewModel {
    /// Groups and sorts the given trips for display.
    ///
    /// - Current: in progress now, soonest-ending first.
    /// - Upcoming: starts in the future, soonest-starting first.
    /// - Past: already ended, most-recent first.
    func sections(from trips: [Trip], now: Date = Date()) -> [TripSection] {
        var current: [Trip] = []
        var upcoming: [Trip] = []
        var past: [Trip] = []

        for trip in trips {
            switch trip.status(now: now) {
            case .current: current.append(trip)
            case .upcoming: upcoming.append(trip)
            case .past: past.append(trip)
            }
        }

        current.sort { $0.endDate < $1.endDate }
        upcoming.sort { $0.startDate < $1.startDate }
        past.sort { $0.endDate > $1.endDate }

        return [
            TripSection(status: .current, trips: current),
            TripSection(status: .upcoming, trips: upcoming),
            TripSection(status: .past, trips: past),
        ].filter { !$0.trips.isEmpty }
    }
}
