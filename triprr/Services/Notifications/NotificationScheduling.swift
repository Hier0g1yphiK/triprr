//
//  NotificationScheduling.swift
//  triprr
//
//  Local reminders for flights and timed activities (Req 8). A `Sendable`
//  protocol, injected via `AppServices`, is what the app depends on so previews
//  and tests substitute a no-op/mock freely. The concrete
//  `LocalNotificationScheduler` wraps `UNUserNotificationCenter`.
//
//  The design keeps the testable logic — identifier derivation, fire-date
//  computation (start − lead), skip-if-past, and the title/body content strings
//  phrased in the item's local zone — in pure types (`NotificationPlanner`,
//  `NotificationLeadTimes`, `ScheduledNotification`) that never touch
//  UserNotifications. The scheduler itself stays thin: it computes plans with
//  the planner and forwards them to a `UserNotificationCenter` abstraction, so
//  the whole scheduling behaviour can be unit-tested against a spy center
//  without the real `UNUserNotificationCenter` and without the system prompt.
//
//  Authorization is requested lazily (on the first scheduling attempt) rather
//  than aggressively at launch, so the user only sees the system prompt when a
//  reminder actually needs to be set. Denial (or a restricted state) makes
//  scheduling a safe no-op: the rest of the app keeps working and never blocks
//  or crashes (Req 8.1, 8.4).
//

import Foundation
import UserNotifications

// MARK: - Configuration

/// How far before an item's start a reminder fires. Both default to sensible
/// values and are configurable per scheduler (Req 8.2).
nonisolated struct NotificationLeadTimes: Hashable, Sendable {
    /// Lead time before a flight's scheduled departure. Default: 2 hours.
    var flight: TimeInterval
    /// Lead time before a timed activity's start. Default: 30 minutes.
    var activity: TimeInterval

    init(flight: TimeInterval = 2 * 3600, activity: TimeInterval = 30 * 60) {
        self.flight = flight
        self.activity = activity
    }

    /// The documented defaults: 2 hours for flights, 30 minutes for activities.
    static let `default` = NotificationLeadTimes()
}

// MARK: - Plan

/// A fully-resolved reminder ready to hand to the notification center. All the
/// decisions (identifier, fire instant, content) are made by the pure
/// `NotificationPlanner`; this value carries nothing framework-specific.
nonisolated struct ScheduledNotification: Hashable, Sendable {
    /// A stable identifier derived from the model id, so rescheduling the same
    /// item replaces its pending request cleanly (e.g. "flight-<uuid>").
    let identifier: String
    /// The UTC instant the notification should fire (item start − lead time).
    let fireDate: Date
    let title: String
    let body: String
}

// MARK: - Authorization

/// A storable snapshot of notification authorization, mirroring
/// `UNAuthorizationStatus` without leaking the framework type to callers.
nonisolated enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    /// Parental controls / MDM restrict notifications.
    case restricted

    /// Whether scheduling should proceed. Denied/restricted make scheduling a
    /// no-op (Req 8.1, 8.4).
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional: true
        case .notDetermined, .denied, .restricted: false
        }
    }
}

// MARK: - Pure planner

/// The pure, fully-testable core of the feature. Turns flights and activities
/// into `ScheduledNotification`s (or `nil` when there is nothing to schedule),
/// with no dependency on `UNUserNotificationCenter`. Every rule the tests pin
/// down lives here: identifier derivation, fire-date = start − lead,
/// skip-if-past, and the zone-aware content strings.
nonisolated enum NotificationPlanner {

    // MARK: Identifiers

    /// Stable identifier for a flight reminder, e.g. "flight-<uuid>".
    static func identifier(forFlight id: UUID) -> String { "flight-\(id.uuidString)" }

    /// Stable identifier for an activity reminder, e.g. "activity-<uuid>".
    static func identifier(forActivity id: UUID) -> String { "activity-\(id.uuidString)" }

    // MARK: Fire date

    /// The fire instant for a reminder: the item's start minus the lead time.
    static func fireDate(start: Date, lead: TimeInterval) -> Date {
        start.addingTimeInterval(-lead)
    }

    // MARK: Plans

    /// A reminder for a flight, or `nil` when the fire time is already in the
    /// past (so a past-dated flight is never scheduled). `now` is injectable
    /// for testing.
    static func plan(
        for flight: Flight,
        leadTimes: NotificationLeadTimes = .default,
        now: Date = Date()
    ) -> ScheduledNotification? {
        let fire = fireDate(start: flight.scheduledDeparture, lead: leadTimes.flight)
        guard fire > now else { return nil }
        return ScheduledNotification(
            identifier: identifier(forFlight: flight.id),
            fireDate: fire,
            title: flightTitle(for: flight),
            body: flightBody(for: flight, lead: leadTimes.flight)
        )
    }

    /// A reminder for a timed activity, or `nil` when it has no start-based
    /// trigger left (fire time already passed). `now` is injectable for testing.
    static func plan(
        for activity: Activity,
        leadTimes: NotificationLeadTimes = .default,
        now: Date = Date()
    ) -> ScheduledNotification? {
        let fire = fireDate(start: activity.startDate, lead: leadTimes.activity)
        guard fire > now else { return nil }
        return ScheduledNotification(
            identifier: identifier(forActivity: activity.id),
            fireDate: fire,
            title: activityTitle(for: activity),
            body: activityBody(for: activity, lead: leadTimes.activity)
        )
    }

    // MARK: Content

    /// A flight reminder title, e.g. "Flight BA005 departs soon".
    static func flightTitle(for flight: Flight) -> String {
        let number = flightLabel(for: flight)
        return number.isEmpty ? "Upcoming flight" : "Flight \(number) departs soon"
    }

    /// A flight reminder body phrased in the departure airport's local zone,
    /// e.g. "Departs in 2 hours at 09:30 JST from Haneda Airport".
    static func flightBody(for flight: Flight, lead: TimeInterval) -> String {
        let zone = flight.departureTimeZone
        let time = DateHelpers.timeStringWithZone(flight.scheduledDeparture, in: zone)
        let lead = leadPhrase(lead)
        let airport = flight.departureAirport.name
        if airport.isEmpty {
            return "Departs in \(lead) at \(time)."
        }
        return "Departs in \(lead) at \(time) from \(airport)."
    }

    /// An activity reminder title, e.g. "Museum starts soon".
    static func activityTitle(for activity: Activity) -> String {
        let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Upcoming activity" : "\(title) starts soon"
    }

    /// An activity reminder body phrased in the activity's local zone, e.g.
    /// "Starts in 30 minutes at 14:00 JST".
    static func activityBody(for activity: Activity, lead: TimeInterval) -> String {
        let zone = activity.effectiveTimeZone
        let time = DateHelpers.timeStringWithZone(activity.startDate, in: zone)
        return "Starts in \(leadPhrase(lead)) at \(time)."
    }

    /// A combined "AA123" label from airline code + number where available.
    private static func flightLabel(for flight: Flight) -> String {
        let number = flight.flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number
    }

    /// A friendly lead-time phrase, e.g. "2 hours", "30 minutes", "1 hour 30 minutes".
    static func leadPhrase(_ lead: TimeInterval) -> String {
        let totalMinutes = max(1, Int((lead / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        func unit(_ value: Int, _ singular: String) -> String {
            "\(value) \(singular)\(value == 1 ? "" : "s")"
        }
        switch (hours, minutes) {
        case (0, _): return unit(minutes, "minute")
        case (_, 0): return unit(hours, "hour")
        default: return "\(unit(hours, "hour")) \(unit(minutes, "minute"))"
        }
    }
}

// MARK: - Scheduling protocol

/// Schedules, reschedules and cancels local reminders for a trip's flights and
/// timed activities. `Sendable` so it can be stored in `AppServices` and called
/// from view models after create/edit/delete to keep reminders in sync
/// (Req 8.3). All methods are safe no-ops when notifications are denied,
/// restricted, or unavailable (Req 8.1, 8.4).
nonisolated protocol NotificationScheduling: Sendable {
    /// The lead times this scheduler uses (configurable; documented defaults).
    var leadTimes: NotificationLeadTimes { get }

    /// Requests authorization if it has not been determined yet and returns the
    /// resulting status. Safe to call repeatedly; only the first call that finds
    /// `.notDetermined` shows the system prompt.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> NotificationAuthorization

    /// The current authorization status, without prompting.
    func authorizationStatus() async -> NotificationAuthorization

    /// Schedules (or reschedules) a reminder for one flight. Replaces any
    /// existing request with the same identifier. A past-dated flight has its
    /// pending reminder cancelled.
    func sync(flight: Flight) async

    /// Schedules (or reschedules) a reminder for one activity. Replaces any
    /// existing request with the same identifier. A past-dated activity has its
    /// pending reminder cancelled.
    func sync(activity: Activity) async

    /// Reschedules reminders for every flight and timed activity on the trip.
    func syncAll(for trip: Trip) async

    /// Cancels the reminder for a deleted flight.
    func cancel(flightID: UUID) async

    /// Cancels the reminder for a deleted activity.
    func cancel(activityID: UUID) async
}

nonisolated extension NotificationScheduling {
    /// The identifier a flight reminder uses (so delete flows can cancel by id).
    func identifier(forFlight id: UUID) -> String { NotificationPlanner.identifier(forFlight: id) }
    /// The identifier an activity reminder uses.
    func identifier(forActivity id: UUID) -> String { NotificationPlanner.identifier(forActivity: id) }
}

// MARK: - UNUserNotificationCenter abstraction

/// A thin seam over the parts of `UNUserNotificationCenter` the scheduler uses.
/// `LocalNotificationScheduler` talks to this instead of the concrete center so
/// tests inject a spy and never touch the system (which would prompt the user
/// and can't run under the unit suite).
nonisolated protocol UserNotificationCenter: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func add(_ notification: ScheduledNotification) async
    func removePending(identifiers: [String]) async
}

/// The live center backed by `UNUserNotificationCenter`. Thin: it only maps the
/// framework types and forwards. iOS and macOS both support UserNotifications,
/// so no platform guard is needed here.
nonisolated struct SystemNotificationCenter: UserNotificationCenter {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // A failed request is treated as "not granted"; the app keeps
            // working and scheduling becomes a no-op (Req 8.4).
        }
        return await authorizationStatus()
    }

    func add(_ notification: ScheduledNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let interval = max(1, notification.fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger
        )
        // Adding with an existing identifier replaces the pending request, so a
        // reschedule is just a re-add.
        try? await center.add(request)
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .authorized
        @unknown default: .denied
        }
    }
}

// MARK: - Live scheduler

/// Schedules reminders with `UNUserNotificationCenter` via the injectable
/// `UserNotificationCenter` seam. Authorization is requested lazily on the first
/// scheduling attempt; denial/restriction makes every scheduling call a safe
/// no-op (Req 8.1, 8.2, 8.4).
nonisolated struct LocalNotificationScheduler: NotificationScheduling {
    let leadTimes: NotificationLeadTimes
    private let center: any UserNotificationCenter

    init(
        leadTimes: NotificationLeadTimes = .default,
        center: any UserNotificationCenter = SystemNotificationCenter()
    ) {
        self.leadTimes = leadTimes
        self.center = center
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> NotificationAuthorization {
        let status = await center.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await center.requestAuthorization()
    }

    func authorizationStatus() async -> NotificationAuthorization {
        await center.authorizationStatus()
    }

    func sync(flight: Flight) async {
        guard await ensureAuthorized() else { return }
        let identifier = NotificationPlanner.identifier(forFlight: flight.id)
        if let plan = NotificationPlanner.plan(for: flight, leadTimes: leadTimes) {
            await center.add(plan)
        } else {
            // Past-dated or cleared: make sure no stale reminder lingers.
            await center.removePending(identifiers: [identifier])
        }
    }

    func sync(activity: Activity) async {
        guard await ensureAuthorized() else { return }
        let identifier = NotificationPlanner.identifier(forActivity: activity.id)
        if let plan = NotificationPlanner.plan(for: activity, leadTimes: leadTimes) {
            await center.add(plan)
        } else {
            await center.removePending(identifiers: [identifier])
        }
    }

    func syncAll(for trip: Trip) async {
        guard await ensureAuthorized() else { return }
        for flight in trip.flights {
            await sync(flight: flight)
        }
        for activity in trip.activities {
            await sync(activity: activity)
        }
    }

    func cancel(flightID: UUID) async {
        await center.removePending(identifiers: [NotificationPlanner.identifier(forFlight: flightID)])
    }

    func cancel(activityID: UUID) async {
        await center.removePending(identifiers: [NotificationPlanner.identifier(forActivity: activityID)])
    }

    /// Lazily requests authorization and reports whether scheduling may proceed.
    private func ensureAuthorized() async -> Bool {
        await requestAuthorizationIfNeeded().allowsScheduling
    }
}

// MARK: - No-op scheduler (previews/tests)

/// A scheduler that does nothing. Used in previews and as the default test
/// double so views and view models exercise the sync calls without touching the
/// system notification center.
nonisolated struct NoopNotificationScheduler: NotificationScheduling {
    let leadTimes: NotificationLeadTimes

    init(leadTimes: NotificationLeadTimes = .default) {
        self.leadTimes = leadTimes
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> NotificationAuthorization { .denied }
    func authorizationStatus() async -> NotificationAuthorization { .denied }
    func sync(flight: Flight) async {}
    func sync(activity: Activity) async {}
    func syncAll(for trip: Trip) async {}
    func cancel(flightID: UUID) async {}
    func cancel(activityID: UUID) async {}
}
