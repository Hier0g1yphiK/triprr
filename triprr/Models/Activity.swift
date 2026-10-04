//
//  Activity.swift
//  triprr
//
//  A day-itinerary entry: a visit, meal, free-form plan, or an added
//  suggestion. Owns its own notes and links.
//

import Foundation
import SwiftData

@Model
final class Activity {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = ActivityCategory.other.rawValue
    /// Stored in UTC; displayed in `effectiveTimeZone`.
    var startDate: Date = Date()
    /// Optional end of a time range.
    var endDate: Date?
    var timeZoneIdentifier: String?
    var place: Place?
    var notes: String?
    var isDone: Bool = false
    /// Tiebreak for ordering items that share a start time (Req 4.3).
    var sortOrder: Int = 0
    /// Optional per-activity override of the travel mode used to reach it.
    var travelModeRaw: String?
    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Note.activity)
    var activityNotes: [Note] = []
    @Relationship(deleteRule: .cascade, inverse: \LinkItem.activity)
    var links: [LinkItem] = []

    init(
        id: UUID = UUID(),
        title: String = "",
        category: ActivityCategory = .other,
        startDate: Date,
        endDate: Date? = nil,
        timeZoneIdentifier: String? = nil,
        place: Place? = nil,
        notes: String? = nil,
        isDone: Bool = false,
        sortOrder: Int = 0,
        travelMode: TravelMode? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.title = title
        self.categoryRaw = category.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.place = place
        self.notes = notes
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.travelModeRaw = travelMode?.rawValue
        self.trip = trip
    }
}

extension Activity {
    var category: ActivityCategory {
        get { ActivityCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var travelMode: TravelMode? {
        get { travelModeRaw.flatMap(TravelMode.init(rawValue:)) }
        set { travelModeRaw = newValue?.rawValue }
    }

    var effectiveTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? place?.timeZone
            ?? trip?.primaryTimeZone
            ?? .current
    }
}
