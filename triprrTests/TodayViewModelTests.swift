//
//  TodayViewModelTests.swift
//  triprrTests
//
//  Unit tests for the Today screen's view model (Req 7). They verify, with an
//  injected `now`, that the VM:
//  - picks the ACTIVE trip (in progress now, soonest-ending wins) and its
//    active day (Req 7.1);
//  - computes CURRENT and NEXT against `now` in the trip's local zone — mid-
//    item, between items, before the first item, and after the last (Req 7.1,
//    7.3);
//  - falls back to a sensible state when nothing is in progress: the soonest
//    upcoming trip with a countdown, or an empty "no trip" state (Req 7.2);
//  - evaluates boundaries (trip start/end day, item start/end instants) in the
//    place's local zone rather than the device's.
//

import Testing
import Foundation
@testable import triprr

@MainActor
struct TodayViewModelTests {

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// A Tokyo-local instant for a given day offset from `baseDay` and hour.
    private func tokyoInstant(day: Date, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func startOfTokyoDay(_ date: Date) -> Date {
        DateHelpers.startOfDay(for: date, in: tokyo)
    }

    private var tokyoPlace: Place {
        Place(
            name: "Tokyo Station",
            latitude: 35.6812, longitude: 139.7671,
            address: "Tokyo, Japan",
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    /// Builds a Tokyo trip spanning `[startDay, endDay]` with activities placed
    /// at the given Tokyo wall-clock (hour, duration-minutes) pairs on `day`.
    private func makeTokyoTrip(
        startDay: Date,
        endDay: Date,
        day: Date,
        activities: [(title: String, hour: Int, durationMinutes: Int?)]
    ) -> Trip {
        let trip = Trip(
            name: "Tokyo",
            startDate: startOfTokyoDay(startDay),
            endDate: startOfTokyoDay(endDay)
        )
        trip.destinations = [Destination(place: tokyoPlace, sortOrder: 0, trip: trip)]
        trip.activities = activities.enumerated().map { index, spec in
            let start = tokyoInstant(day: day, hour: spec.hour)
            let end = spec.durationMinutes.map { start.addingTimeInterval(Double($0) * 60) }
            return Activity(
                title: spec.title,
                category: .other,
                startDate: start,
                endDate: end,
                timeZoneIdentifier: "Asia/Tokyo",
                place: tokyoPlace,
                sortOrder: index,
                trip: trip
            )
        }
        return trip
    }

    // MARK: - Active trip / day selection (Req 7.1)

    @Test func picksInProgressTripAsActive() {
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let end = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: today,
            activities: [("Lunch", 12, 60)]
        )
        let vm = TodayViewModel(trips: [trip], now: today)
        #expect(vm.hasActiveTrip)
        #expect(vm.activeDay?.trip.id == trip.id)
    }

    @Test func activeDayIsTodayInTripZone() {
        let now = tokyoInstant(day: Date(), hour: 10)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: 3, to: now)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: now,
            activities: [("Breakfast", 8, 60)]
        )
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.dayStart == startOfTokyoDay(now))
    }

    @Test func picksSoonestEndingWhenMultipleInProgress() {
        let today = Date()
        let shortEnd = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let longEnd = Calendar.current.date(byAdding: .day, value: 5, to: today)!
        let start = Calendar.current.date(byAdding: .day, value: -2, to: today)!

        let longer = makeTokyoTrip(startDay: start, endDay: longEnd, day: today, activities: [])
        longer.name = "Longer"
        let shorter = makeTokyoTrip(startDay: start, endDay: shortEnd, day: today, activities: [])
        shorter.name = "Shorter"

        let vm = TodayViewModel(trips: [longer, shorter], now: today)
        #expect(vm.activeDay?.trip.name == "Shorter")
    }

    // MARK: - Current / next (Req 7.1, 7.3)

    @Test func currentIsItemSpanningNow() {
        let day = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: day,
            activities: [
                ("Breakfast", 8, 60),   // 08:00–09:00
                ("Museum", 10, 120),    // 10:00–12:00
                ("Dinner", 19, 90),     // 19:00–20:30
            ]
        )
        // 10:30 Tokyo: inside the Museum window.
        let now = tokyoInstant(day: day, hour: 10, minute: 30)
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.current?.title == "Museum")
        #expect(vm.activeDay?.next?.title == "Dinner")
    }

    @Test func currentFallsBackToMostRecentlyStartedBetweenItems() {
        let day = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: day,
            activities: [
                ("Breakfast", 8, 60),   // 08:00–09:00
                ("Museum", 10, 120),    // 10:00–12:00
                ("Dinner", 19, 90),     // 19:00–20:30
            ]
        )
        // 13:00 Tokyo: between Museum (ended 12:00) and Dinner (starts 19:00).
        let now = tokyoInstant(day: day, hour: 13)
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.current?.title == "Museum")
        #expect(vm.activeDay?.next?.title == "Dinner")
    }

    @Test func beforeFirstItemHasNoCurrentButHasNext() {
        let day = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: day,
            activities: [
                ("Breakfast", 8, 60),
                ("Museum", 10, 120),
            ]
        )
        // 06:00 Tokyo: before anything has started.
        let now = tokyoInstant(day: day, hour: 6)
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.current == nil)
        #expect(vm.activeDay?.next?.title == "Breakfast")
    }

    @Test func afterLastItemHasCurrentButNoNext() {
        let day = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: day,
            activities: [
                ("Breakfast", 8, 60),
                ("Dinner", 19, 90),     // ends 20:30
            ]
        )
        // 22:00 Tokyo: everything has started/ended.
        let now = tokyoInstant(day: day, hour: 22)
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.current?.title == "Dinner")
        #expect(vm.activeDay?.next == nil)
    }

    @Test func nextIsStrictlyAfterNowAtExactStartBoundary() {
        let day = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: end, day: day,
            activities: [
                ("Museum", 10, 120),    // 10:00–12:00
                ("Dinner", 19, 90),
            ]
        )
        // Exactly 10:00 Tokyo: the Museum is "now" (start <= now <= end), so the
        // next upcoming item is Dinner.
        let now = tokyoInstant(day: day, hour: 10)
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.activeDay?.current?.title == "Museum")
        #expect(vm.activeDay?.next?.title == "Dinner")
    }

    // MARK: - No active trip (Req 7.2)

    @Test func noTripsGivesNoTripState() {
        let vm = TodayViewModel(trips: [], now: Date())
        #expect(vm.state == .noTrip)
        #expect(vm.hasActiveTrip == false)
    }

    @Test func surfacesUpcomingTripWithCountdownWhenNoneInProgress() {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now)!
        let trip = makeTokyoTrip(startDay: start, endDay: end, day: start, activities: [])
        let vm = TodayViewModel(trips: [trip], now: now)

        #expect(vm.hasActiveTrip == false)
        guard case .upcoming(let up) = vm.state else {
            Issue.record("Expected .upcoming, got \(vm.state)")
            return
        }
        #expect(up.trip.id == trip.id)
        if case .upcoming = up.countdown {} else {
            Issue.record("Expected an upcoming countdown, got \(up.countdown)")
        }
    }

    @Test func picksSoonestStartingUpcomingTrip() {
        let now = Date()
        let soonStart = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let soonEnd = Calendar.current.date(byAdding: .day, value: 8, to: now)!
        let laterStart = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        let laterEnd = Calendar.current.date(byAdding: .day, value: 33, to: now)!

        let later = makeTokyoTrip(startDay: laterStart, endDay: laterEnd, day: laterStart, activities: [])
        later.name = "Later"
        let soon = makeTokyoTrip(startDay: soonStart, endDay: soonEnd, day: soonStart, activities: [])
        soon.name = "Soon"

        let vm = TodayViewModel(trips: [later, soon], now: now)
        #expect(vm.upcomingTrip?.trip.name == "Soon")
    }

    @Test func inProgressBeatsUpcoming() {
        let now = Date()
        let activeStart = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let activeEnd = Calendar.current.date(byAdding: .day, value: 2, to: now)!
        let upcomingStart = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let upcomingEnd = Calendar.current.date(byAdding: .day, value: 8, to: now)!

        let active = makeTokyoTrip(startDay: activeStart, endDay: activeEnd, day: now, activities: [])
        active.name = "Active"
        let upcoming = makeTokyoTrip(startDay: upcomingStart, endDay: upcomingEnd, day: upcomingStart, activities: [])
        upcoming.name = "Upcoming"

        let vm = TodayViewModel(trips: [upcoming, active], now: now)
        #expect(vm.activeDay?.trip.name == "Active")
    }

    // MARK: - Trip-range boundaries (Req 7.1, 7.3)

    @Test func tripIsActiveOnItsLastDay() {
        // A trip ending today should still be "in progress" through the end of
        // its last local day.
        let now = tokyoInstant(day: Date(), hour: 14)
        let start = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let trip = makeTokyoTrip(
            startDay: start, endDay: now, day: now,
            activities: [("Farewell lunch", 12, 90)]
        )
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.hasActiveTrip)
        #expect(vm.activeDay?.trip.id == trip.id)
    }

    @Test func tripIsNotActiveTheDayAfterItEnds() {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let trip = makeTokyoTrip(startDay: start, endDay: end, day: start, activities: [])
        let vm = TodayViewModel(trips: [trip], now: now)
        #expect(vm.hasActiveTrip == false)
        #expect(vm.state == .noTrip)
    }

    // MARK: - Static current/next helpers on raw entries

    @Test func currentAndNextHelpersHandleEmptyEntries() {
        #expect(TodayViewModel.currentEntry(in: [], now: Date()) == nil)
        #expect(TodayViewModel.nextEntry(in: [], now: Date()) == nil)
    }
}
