//
//  DateHelpers.swift
//  triprr
//
//  Time-zone-aware date utilities. All instants in Triprr are stored as UTC
//  `Date`s; these helpers render and bucket them in the local time zone of the
//  place involved, so a trip abroad shows correct local times and day
//  boundaries regardless of the device's zone.
//

import Foundation

nonisolated enum DateHelpers {

    /// A Gregorian calendar fixed to a given time zone.
    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Day bucketing

    /// The start of the calendar day containing `date`, evaluated in `timeZone`.
    ///
    /// The same instant can fall on different calendar days in different zones;
    /// this resolves the day boundary in the zone that matters for display.
    static func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        calendar(in: timeZone).startOfDay(for: date)
    }

    /// Whether two instants fall on the same calendar day in `timeZone`.
    static func isSameDay(_ a: Date, _ b: Date, in timeZone: TimeZone) -> Bool {
        calendar(in: timeZone).isDate(a, inSameDayAs: b)
    }

    /// The ordered list of day-start instants spanning `start...end` inclusive,
    /// evaluated in `timeZone`. Used to lay out a trip's days.
    static func dayStarts(from start: Date, to end: Date, in timeZone: TimeZone) -> [Date] {
        let cal = calendar(in: timeZone)
        var current = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        guard current <= last else { return [] }
        var days: [Date] = []
        while current <= last {
            days.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// The number of whole calendar days from `start` to `end` in `timeZone`
    /// (0 if same day). Negative if `end` precedes `start`.
    static func dayCount(from start: Date, to end: Date, in timeZone: TimeZone) -> Int {
        let cal = calendar(in: timeZone)
        let a = cal.startOfDay(for: start)
        let b = cal.startOfDay(for: end)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    // MARK: - Formatting

    /// Formats an instant in a given zone, e.g. "09:30".
    static func timeString(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A short zone label for an instant, e.g. "JST" or "GMT+9".
    static func zoneAbbreviation(_ date: Date, in timeZone: TimeZone) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.identifier
    }

    /// Formats an instant in a given zone with an explicit zone label,
    /// e.g. "09:30 JST".
    static func timeStringWithZone(_ date: Date, in timeZone: TimeZone) -> String {
        "\(timeString(date, in: timeZone)) \(zoneAbbreviation(date, in: timeZone))"
    }

    /// A medium date string in a given zone, e.g. "15 Oct 2026".
    static func dateString(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime
            .day().month(.abbreviated).year()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A compact date range, e.g. "15–22 Oct 2026" or "28 Dec 2026 – 3 Jan 2027".
    static func dateRangeString(_ start: Date, _ end: Date, in timeZone: TimeZone) -> String {
        "\(dateString(start, in: timeZone)) – \(dateString(end, in: timeZone))"
    }
}

/// A human-friendly countdown relative to a trip's dates.
nonisolated enum TripCountdown: Equatable {
    case upcoming(days: Int)
    case startsToday
    case inProgress(dayNumber: Int, totalDays: Int)
    case ended

    /// Computes the countdown for a trip in the given time zone.
    static func make(start: Date, end: Date, timeZone: TimeZone, now: Date = Date()) -> TripCountdown {
        let startDay = DateHelpers.startOfDay(for: start, in: timeZone)
        let endDay = DateHelpers.startOfDay(for: end, in: timeZone)
        let today = DateHelpers.startOfDay(for: now, in: timeZone)

        if today < startDay {
            let days = DateHelpers.dayCount(from: today, to: startDay, in: timeZone)
            return days == 0 ? .startsToday : .upcoming(days: days)
        } else if today > endDay {
            return .ended
        } else {
            let dayNumber = DateHelpers.dayCount(from: startDay, to: today, in: timeZone) + 1
            let totalDays = DateHelpers.dayCount(from: startDay, to: endDay, in: timeZone) + 1
            return .inProgress(dayNumber: dayNumber, totalDays: totalDays)
        }
    }

    /// A short label, e.g. "In 12 days", "Day 2 of 7", "Ended".
    var label: String {
        switch self {
        case .upcoming(let days): "In \(days) day\(days == 1 ? "" : "s")"
        case .startsToday: "Starts today"
        case .inProgress(let day, let total): "Day \(day) of \(total)"
        case .ended: "Ended"
        }
    }
}

// MARK: - TimeZone convenience

nonisolated extension TimeZone {
    /// Resolve from an optional identifier, falling back to another zone.
    static func resolved(_ identifier: String?, fallback: TimeZone = .current) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? fallback
    }
}
