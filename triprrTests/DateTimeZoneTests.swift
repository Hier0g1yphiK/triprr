//
//  DateTimeZoneTests.swift
//  triprrTests
//
//  Unit tests for the UTC-storage / local-display time-zone logic. These are
//  the correctness-critical date utilities called out by the quality
//  requirements (Req 10.2, 10.3, 11.4).
//

import Testing
import Foundation
@testable import triprr

struct DateTimeZoneTests {

    // A fixed reference instant: 2026-10-15 00:30:00 UTC.
    // In Tokyo (UTC+9) this is 2026-10-15 09:30. In Los Angeles (PDT, UTC-7)
    // this is 2026-10-14 17:30 — a *different calendar day*.
    private var referenceInstant: Date {
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")
        comps.year = 2026; comps.month = 10; comps.day = 15
        comps.hour = 0; comps.minute = 30
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let london = TimeZone(identifier: "Europe/London")!
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: - UTC storage round-trip

    @Test func instantIsZoneIndependent() {
        // The same Date renders to different wall-clock times per zone, but is
        // one underlying instant.
        let tokyoWall = DateHelpers.timeString(referenceInstant, in: tokyo)
        let laWall = DateHelpers.timeString(referenceInstant, in: losAngeles)
        #expect(tokyoWall != laWall)
        // Round-trip through components back to the same instant.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: referenceInstant)
        let rebuilt = cal.date(from: comps)!
        #expect(abs(rebuilt.timeIntervalSince(referenceInstant)) < 1.0)
    }

    // MARK: - Format in zone

    @Test func formatsInTokyoLocalTime() {
        let s = DateHelpers.timeString(referenceInstant, in: tokyo)
        // 00:30 UTC + 9h = 09:30 in Tokyo. Accept 12h or 24h locale forms.
        #expect(s.contains("9:30") || s.contains("09:30"))
    }

    @Test func formatsInLosAngelesLocalTime() {
        let s = DateHelpers.timeString(referenceInstant, in: losAngeles)
        // 00:30 UTC - 7h (PDT) = 17:30 previous day.
        #expect(s.contains("5:30") || s.contains("17:30"))
    }

    @Test func zoneLabelIsAppended() {
        let s = DateHelpers.timeStringWithZone(referenceInstant, in: tokyo)
        let abbrev = tokyo.abbreviation(for: referenceInstant) ?? "Asia/Tokyo"
        #expect(s.hasSuffix(abbrev))
    }

    // MARK: - Day bucketing across zones

    @Test func sameInstantFallsOnDifferentDaysByZone() {
        let tokyoDay = DateHelpers.startOfDay(for: referenceInstant, in: tokyo)
        let laDay = DateHelpers.startOfDay(for: referenceInstant, in: losAngeles)
        // The same instant buckets to different local days: Tokyo's day-start
        // is 2026-10-15 00:00 JST, LA's is 2026-10-14 00:00 PDT. These are two
        // distinct instants (local midnights of different calendar dates).
        #expect(tokyoDay != laDay)

        var tokyoCal = Calendar(identifier: .gregorian); tokyoCal.timeZone = tokyo
        var laCal = Calendar(identifier: .gregorian); laCal.timeZone = losAngeles
        // The reference instant is the 15th in Tokyo but the 14th in LA.
        #expect(tokyoCal.component(.day, from: referenceInstant) == 15)
        #expect(laCal.component(.day, from: referenceInstant) == 14)
        // And each day-start carries the expected local date.
        #expect(tokyoCal.component(.day, from: tokyoDay) == 15)
        #expect(laCal.component(.day, from: laDay) == 14)
    }

    @Test func dayStartsSpanInclusiveRange() {
        // A 3-day trip in London.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = london
        let start = cal.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 15))!
        let end = cal.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 9))!
        let days = DateHelpers.dayStarts(from: start, to: end, in: london)
        #expect(days.count == 3)
        #expect(DateHelpers.dayCount(from: start, to: end, in: london) == 2)
    }

    @Test func emptyWhenEndBeforeStart() {
        let start = referenceInstant
        let end = start.addingTimeInterval(-86_400)
        #expect(DateHelpers.dayStarts(from: start, to: end, in: utc).isEmpty)
    }

    // MARK: - DST transitions

    @Test func dstSpringForwardDayHas23Hours() {
        // US DST begins 2026-03-08: clocks jump 02:00 -> 03:00 in LA.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = losAngeles
        let dayStart = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
        let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let hours = nextDayStart.timeIntervalSince(dayStart) / 3600
        #expect(abs(hours - 23) < 0.01)
    }

    @Test func dstFallBackDayHas25Hours() {
        // US DST ends 2026-11-01: clocks fall 02:00 -> 01:00 in LA.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = losAngeles
        let dayStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let nextDayStart = cal.date(byAdding: .day, value: 1, to: dayStart)!
        let hours = nextDayStart.timeIntervalSince(dayStart) / 3600
        #expect(abs(hours - 25) < 0.01)
    }

    // MARK: - Date-line flight

    @Test func dateLineFlightArrivesEarlierLocalWallClock() {
        // Depart Tokyo 2026-10-15 17:00 JST, 10h flight to Los Angeles.
        var tokyoCal = Calendar(identifier: .gregorian); tokyoCal.timeZone = tokyo
        let departure = tokyoCal.date(
            from: DateComponents(year: 2026, month: 10, day: 15, hour: 17, minute: 0)
        )!
        let arrival = departure.addingTimeInterval(10 * 3600)

        // Arrival instant is strictly later than departure instant.
        #expect(arrival > departure)

        // But the *local wall-clock day* in LA is the same calendar date (the
        // 15th) and the local time is earlier in the day than departure's local
        // time, illustrating the date-line effect.
        var laCal = Calendar(identifier: .gregorian); laCal.timeZone = losAngeles
        let arrivalDay = laCal.component(.day, from: arrival)
        let arrivalHour = laCal.component(.hour, from: arrival)
        #expect(arrivalDay == 15)
        // 17:00 JST on 10-15 == 01:00 PDT on 10-15; +10h = 11:00 PDT on 10-15.
        #expect(arrivalHour == 11)

        // Displayed in each airport's own zone, both strings are sensible.
        let depStr = DateHelpers.timeString(departure, in: tokyo)
        let arrStr = DateHelpers.timeString(arrival, in: losAngeles)
        #expect(depStr.contains("17:00") || depStr.contains("5:00"))
        #expect(arrStr.contains("11:00"))
    }
}
