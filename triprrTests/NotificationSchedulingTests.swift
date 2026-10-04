//
//  NotificationSchedulingTests.swift
//  triprrTests
//
//  Unit tests for local reminders (Req 8). These cover the pure scheduling
//  logic — identifier derivation, fire-date = start − lead, skip-if-past, and
//  the zone-aware content strings — plus the `LocalNotificationScheduler`
//  behaviour (schedule / reschedule-by-identifier / cancel) exercised against a
//  spy `UserNotificationCenter`, so no test ever touches the real
//  `UNUserNotificationCenter` or triggers the system prompt. A denied/mock
//  authorization is verified to make scheduling a safe no-op (Req 8.1, 8.4).
//

import Testing
import Foundation
@testable import triprr

struct NotificationSchedulingTests {

    // MARK: - Fixtures

    private let tokyoZone = "Asia/Tokyo"
    private let londonZone = "Europe/London"

    private func haneda() -> Place {
        Place(name: "Haneda Airport", latitude: 35.5494, longitude: 139.7798,
              timeZoneIdentifier: tokyoZone)
    }
    private func heathrow() -> Place {
        Place(name: "Heathrow Airport", latitude: 51.4700, longitude: -0.4543,
              timeZoneIdentifier: londonZone)
    }

    /// A flight departing `departure` (UTC), London → Tokyo.
    private func makeFlight(id: UUID = UUID(), departure: Date, number: String = "BA005") -> Flight {
        Flight(
            id: id,
            airline: "British Airways",
            flightNumber: number,
            departureAirport: heathrow(),
            arrivalAirport: haneda(),
            scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(14 * 3600)
        )
    }

    /// A timed activity starting at `start` (UTC) in the Tokyo zone.
    private func makeActivity(id: UUID = UUID(), start: Date, title: String = "Museum") -> Activity {
        Activity(
            id: id,
            title: title,
            category: .museum,
            startDate: start,
            timeZoneIdentifier: tokyoZone
        )
    }

    // MARK: - Identifier derivation

    @Test func flightIdentifierIsStableAndDerivedFromID() {
        let id = UUID()
        let flight = makeFlight(id: id, departure: Date())
        let plan = NotificationPlanner.plan(
            for: flight, now: flight.scheduledDeparture.addingTimeInterval(-10 * 3600)
        )
        #expect(NotificationPlanner.identifier(forFlight: id) == "flight-\(id.uuidString)")
        #expect(plan?.identifier == "flight-\(id.uuidString)")
    }

    @Test func activityIdentifierIsStableAndDerivedFromID() {
        let id = UUID()
        let activity = makeActivity(id: id, start: Date())
        let plan = NotificationPlanner.plan(
            for: activity, now: activity.startDate.addingTimeInterval(-10 * 3600)
        )
        #expect(NotificationPlanner.identifier(forActivity: id) == "activity-\(id.uuidString)")
        #expect(plan?.identifier == "activity-\(id.uuidString)")
    }

    // MARK: - Fire date = start − lead

    @Test func fireDateIsStartMinusLead() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(NotificationPlanner.fireDate(start: start, lead: 3600) == start.addingTimeInterval(-3600))
    }

    @Test func flightFireDateUsesFlightLeadTime() {
        let now = Date()
        let departure = now.addingTimeInterval(10 * 3600)
        let flight = makeFlight(departure: departure)
        let leads = NotificationLeadTimes(flight: 2 * 3600, activity: 30 * 60)
        let plan = NotificationPlanner.plan(for: flight, leadTimes: leads, now: now)
        #expect(plan?.fireDate == departure.addingTimeInterval(-2 * 3600))
    }

    @Test func activityFireDateUsesActivityLeadTime() {
        let now = Date()
        let start = now.addingTimeInterval(10 * 3600)
        let activity = makeActivity(start: start)
        let leads = NotificationLeadTimes(flight: 2 * 3600, activity: 30 * 60)
        let plan = NotificationPlanner.plan(for: activity, leadTimes: leads, now: now)
        #expect(plan?.fireDate == start.addingTimeInterval(-30 * 60))
    }

    @Test func defaultLeadTimesAreTwoHoursAndThirtyMinutes() {
        #expect(NotificationLeadTimes.default.flight == 2 * 3600)
        #expect(NotificationLeadTimes.default.activity == 30 * 60)
    }

    // MARK: - Skip if past

    @Test func pastFlightIsNotScheduled() {
        let now = Date()
        // Fire time (departure − 2h) is already before now.
        let flight = makeFlight(departure: now.addingTimeInterval(30 * 60))
        #expect(NotificationPlanner.plan(for: flight, now: now) == nil)
    }

    @Test func pastActivityIsNotScheduled() {
        let now = Date()
        // Started 10 minutes ago → fire time long past.
        let activity = makeActivity(start: now.addingTimeInterval(-10 * 60))
        #expect(NotificationPlanner.plan(for: activity, now: now) == nil)
    }

    @Test func futureItemsAreScheduled() {
        let now = Date()
        let flight = makeFlight(departure: now.addingTimeInterval(10 * 3600))
        let activity = makeActivity(start: now.addingTimeInterval(10 * 3600))
        #expect(NotificationPlanner.plan(for: flight, now: now) != nil)
        #expect(NotificationPlanner.plan(for: activity, now: now) != nil)
    }

    // MARK: - Content strings (in the item's local zone)

    @Test func flightContentNamesFlightAndLocalDepartureTime() {
        let now = Date()
        let departure = now.addingTimeInterval(10 * 3600)
        let flight = makeFlight(departure: departure, number: "BA005")
        let plan = NotificationPlanner.plan(for: flight, now: now)
        let body = try? #require(plan?.body)

        #expect(plan?.title == "Flight BA005 departs soon")
        // Phrased in the departure airport's (London) local zone.
        let zone = TimeZone(identifier: londonZone)!
        let expectedTime = DateHelpers.timeStringWithZone(departure, in: zone)
        #expect(body?.contains(expectedTime) == true)
        #expect(body?.contains("2 hours") == true)
        #expect(body?.contains("Heathrow Airport") == true)
    }

    @Test func activityContentNamesTitleAndLocalStartTime() {
        let now = Date()
        let start = now.addingTimeInterval(10 * 3600)
        let activity = makeActivity(start: start, title: "Museum")
        let plan = NotificationPlanner.plan(for: activity, now: now)
        let body = try? #require(plan?.body)

        #expect(plan?.title == "Museum starts soon")
        let zone = TimeZone(identifier: tokyoZone)!
        let expectedTime = DateHelpers.timeStringWithZone(start, in: zone)
        #expect(body?.contains(expectedTime) == true)
        #expect(body?.contains("30 minutes") == true)
    }

    @Test func leadPhraseFormatsHoursMinutesAndCombos() {
        #expect(NotificationPlanner.leadPhrase(2 * 3600) == "2 hours")
        #expect(NotificationPlanner.leadPhrase(3600) == "1 hour")
        #expect(NotificationPlanner.leadPhrase(30 * 60) == "30 minutes")
        #expect(NotificationPlanner.leadPhrase(60) == "1 minute")
        #expect(NotificationPlanner.leadPhrase(90 * 60) == "1 hour 30 minutes")
    }

    // MARK: - Authorization gating

    @Test func authorizationAllowsSchedulingOnlyWhenGranted() {
        #expect(NotificationAuthorization.authorized.allowsScheduling)
        #expect(NotificationAuthorization.provisional.allowsScheduling)
        #expect(!NotificationAuthorization.notDetermined.allowsScheduling)
        #expect(!NotificationAuthorization.denied.allowsScheduling)
        #expect(!NotificationAuthorization.restricted.allowsScheduling)
    }

    // MARK: - Scheduler behaviour against a spy center

    @Test func schedulerAddsReminderForFutureFlight() async {
        let center = SpyNotificationCenter(initialStatus: .authorized)
        let scheduler = LocalNotificationScheduler(center: center)
        let flight = makeFlight(departure: Date().addingTimeInterval(10 * 3600))

        await scheduler.sync(flight: flight)

        let added = await center.added
        #expect(added.count == 1)
        #expect(added.first?.identifier == scheduler.identifier(forFlight: flight.id))
    }

    @Test func reschedulingReplacesByIdentifier() async {
        let center = SpyNotificationCenter(initialStatus: .authorized)
        let scheduler = LocalNotificationScheduler(center: center)
        let id = UUID()

        let first = makeFlight(id: id, departure: Date().addingTimeInterval(10 * 3600))
        await scheduler.sync(flight: first)
        // Edit the time; same id → same identifier.
        let edited = makeFlight(id: id, departure: Date().addingTimeInterval(20 * 3600))
        await scheduler.sync(flight: edited)

        let added = await center.added
        // Both adds use the same stable identifier, so the center replaces the
        // pending request cleanly (Req 8.3).
        #expect(added.count == 2)
        #expect(Set(added.map(\.identifier)).count == 1)
        #expect(added.allSatisfy { $0.identifier == scheduler.identifier(forFlight: id) })
    }

    @Test func syncingPastItemCancelsStalePendingReminder() async {
        let center = SpyNotificationCenter(initialStatus: .authorized)
        let scheduler = LocalNotificationScheduler(center: center)
        // Fire time already in the past → not scheduled, stale request removed.
        let flight = makeFlight(departure: Date().addingTimeInterval(30 * 60))

        await scheduler.sync(flight: flight)

        let added = await center.added
        let removed = await center.removed
        #expect(added.isEmpty)
        #expect(removed.contains(scheduler.identifier(forFlight: flight.id)))
    }

    @Test func cancelRemovesByIdentifier() async {
        let center = SpyNotificationCenter(initialStatus: .authorized)
        let scheduler = LocalNotificationScheduler(center: center)
        let flightID = UUID()
        let activityID = UUID()

        await scheduler.cancel(flightID: flightID)
        await scheduler.cancel(activityID: activityID)

        let removed = await center.removed
        #expect(removed.contains(scheduler.identifier(forFlight: flightID)))
        #expect(removed.contains(scheduler.identifier(forActivity: activityID)))
    }

    @Test func deniedAuthorizationMakesSchedulingANoOp() async {
        let center = SpyNotificationCenter(initialStatus: .denied)
        let scheduler = LocalNotificationScheduler(center: center)
        let flight = makeFlight(departure: Date().addingTimeInterval(10 * 3600))
        let activity = makeActivity(start: Date().addingTimeInterval(10 * 3600))

        await scheduler.sync(flight: flight)
        await scheduler.sync(activity: activity)

        let added = await center.added
        #expect(added.isEmpty)
        // No prompt happened and nothing was scheduled; the app keeps working
        // (Req 8.1, 8.4).
        let requested = await center.didRequestAuthorization
        #expect(requested == false)
    }

    @Test func notDeterminedTriggersASingleAuthorizationRequest() async {
        // Starts undetermined; the spy grants on request. The first scheduling
        // attempt prompts once, then schedules.
        let center = SpyNotificationCenter(initialStatus: .notDetermined, grantsOnRequest: true)
        let scheduler = LocalNotificationScheduler(center: center)
        let flight = makeFlight(departure: Date().addingTimeInterval(10 * 3600))

        await scheduler.sync(flight: flight)

        let requested = await center.didRequestAuthorization
        let added = await center.added
        #expect(requested == true)
        #expect(added.count == 1)
    }

    @Test func noopSchedulerNeverSchedules() async {
        let scheduler = NoopNotificationScheduler()
        let flight = makeFlight(departure: Date().addingTimeInterval(10 * 3600))
        // Exercising every entry point must simply do nothing and not crash.
        await scheduler.sync(flight: flight)
        await scheduler.cancel(flightID: flight.id)
        let status = await scheduler.authorizationStatus()
        #expect(status == .denied)
    }
}

// MARK: - Spy center

/// A test double for `UserNotificationCenter` that records what the scheduler
/// does without touching the real `UNUserNotificationCenter`. An `actor` so it
/// is `Sendable` and safe to mutate from the scheduler's async calls.
private actor SpyNotificationCenter: UserNotificationCenter {
    private(set) var added: [ScheduledNotification] = []
    private(set) var removed: [String] = []
    private(set) var didRequestAuthorization = false

    private var status: NotificationAuthorization
    private let grantsOnRequest: Bool

    init(initialStatus: NotificationAuthorization, grantsOnRequest: Bool = false) {
        self.status = initialStatus
        self.grantsOnRequest = grantsOnRequest
    }

    func authorizationStatus() async -> NotificationAuthorization { status }

    func requestAuthorization() async -> NotificationAuthorization {
        didRequestAuthorization = true
        status = grantsOnRequest ? .authorized : .denied
        return status
    }

    func add(_ notification: ScheduledNotification) async {
        added.append(notification)
    }

    func removePending(identifiers: [String]) async {
        removed.append(contentsOf: identifiers)
    }
}
