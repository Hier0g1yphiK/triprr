//
//  FlightEditViewModel.swift
//  triprr
//
//  Backs the flight editor: full manual entry for a flight (airline, flight
//  number, departure/arrival airports, scheduled departure/arrival instants
//  each with their own time zone, plus optional terminal, gate, booking
//  reference, seat and notes). Instants are stored in UTC; each airport's zone
//  defaults from its Place but can be picked/confirmed by the user (Req 2.1).
//  Create/edit are persisted via the ModelContext (Req 2.6).
//

import Foundation
import SwiftData

@MainActor
@Observable
final class FlightEditViewModel {
    enum Mode {
        case create(Trip)
        case edit(Flight)
    }

    /// The lookup action's current state, surfaced by the editor.
    enum LookupState: Equatable {
        case idle
        case loading
        /// A looked-up flight was mapped into the form.
        case filled
        /// The lookup failed; manual entry remains fully available (Req 2.5).
        case failed(String)
    }

    let mode: Mode

    /// Looks up flight details to autofill the form. Defaults to the mock so
    /// previews/tests work without injection; the view supplies the app's
    /// service from the environment. The VM depends only on the protocol
    /// (Req 2.4).
    private var flightLookup: any FlightLookupService

    // MARK: - Form state

    var airline: String = ""
    var flightNumber: String = ""

    var departureAirport: Place?
    var arrivalAirport: Place?

    /// Wall-clock components the user picks; combined with the chosen zone to
    /// produce the stored UTC instant.
    var departureLocalTime: Date = Date()
    var arrivalLocalTime: Date = Date()

    /// Per-airport IANA time-zone identifiers (default from the airport place).
    var departureZoneIdentifier: String = TimeZone.current.identifier
    var arrivalZoneIdentifier: String = TimeZone.current.identifier

    var terminal: String = ""
    var gate: String = ""
    var bookingReference: String = ""
    var seat: String = ""
    var notes: String = ""

    // MARK: - Lookup state

    /// The current state of the "look up" action.
    private(set) var lookupState: LookupState = .idle

    init(mode: Mode, flightLookup: any FlightLookupService = MockFlightLookupService()) {
        self.mode = mode
        self.flightLookup = flightLookup
        load()
    }

    /// Injects the lookup service from the environment once the view appears,
    /// since the service container isn't available at `init`.
    func use(flightLookup: any FlightLookupService) {
        self.flightLookup = flightLookup
    }

    // MARK: - Derived

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var departureTimeZone: TimeZone {
        TimeZone(identifier: departureZoneIdentifier) ?? .current
    }

    var arrivalTimeZone: TimeZone {
        TimeZone(identifier: arrivalZoneIdentifier) ?? .current
    }

    /// The UTC instant for the departure, built from the picked local time
    /// interpreted in the chosen departure zone.
    var departureInstant: Date {
        instant(from: departureLocalTime, in: departureTimeZone)
    }

    /// The UTC instant for the arrival, built from the picked local time
    /// interpreted in the chosen arrival zone.
    var arrivalInstant: Date {
        instant(from: arrivalLocalTime, in: arrivalTimeZone)
    }

    private var hasBothAirports: Bool {
        departureAirport != nil && arrivalAirport != nil
    }

    /// At least one of airline/number so the flight has an identity, plus both
    /// airports, plus arrival not before departure.
    var canSave: Bool {
        let hasIdentity = !airline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasIdentity && hasBothAirports && arrivalInstant >= departureInstant
    }

    /// Whether arrival precedes departure (shown as a validation message).
    var arrivalBeforeDeparture: Bool {
        hasBothAirports && arrivalInstant < departureInstant
    }

    /// A flight number is required to look up a flight. The lookup is disabled
    /// while a request is in flight.
    var canLookUp: Bool {
        !flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && lookupState != .loading
    }

    /// Whether a lookup is currently running.
    var isLookingUp: Bool { lookupState == .loading }

    /// The error message to show, if the last lookup failed.
    var lookupErrorMessage: String? {
        if case let .failed(message) = lookupState { return message }
        return nil
    }

    // MARK: - Lookup

    /// Looks up the entered flight number for the departure date and, on
    /// success, maps the result into the form (airline, both airports with
    /// their zones, scheduled times, terminal/gate). On failure or offline it
    /// records a clear error and leaves everything the user typed intact so
    /// manual entry stays fully available (Req 2.4, 2.5).
    func lookUp() async {
        let number = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return }

        lookupState = .loading
        let query = FlightLookupQuery(flightNumber: number, date: departureInstant)
        do {
            let result = try await flightLookup.lookup(query)
            apply(result)
            lookupState = .filled
        } catch let error as FlightLookupError {
            lookupState = .failed(error.message)
        } catch {
            lookupState = .failed(FlightLookupError.failed.message)
        }
    }

    /// Clears any lookup error/success banner (e.g. when the user edits a
    /// field after a lookup).
    func clearLookupState() {
        if lookupState != .loading { lookupState = .idle }
    }

    /// Maps a lookup result into the form fields, adopting each airport's zone.
    private func apply(_ result: FlightLookupResult) {
        airline = result.airline
        flightNumber = result.flightNumber

        departureAirport = result.departureAirport
        arrivalAirport = result.arrivalAirport
        departureZoneIdentifier = result.departureAirport.timeZoneIdentifier
            ?? departureZoneIdentifier
        arrivalZoneIdentifier = result.arrivalAirport.timeZoneIdentifier
            ?? arrivalZoneIdentifier

        departureLocalTime = localTime(from: result.scheduledDeparture, in: departureTimeZone)
        arrivalLocalTime = localTime(from: result.scheduledArrival, in: arrivalTimeZone)

        if let terminal = result.terminal { self.terminal = terminal }
        if let gate = result.gate { self.gate = gate }
    }

    // MARK: - Airport zone defaults

    /// Adopt the departure airport's zone when it carries one and the user
    /// hasn't already chosen a different zone for an empty slot.
    func departureAirportChanged() {
        guard let identifier = departureAirport?.timeZoneIdentifier else { return }
        departureZoneIdentifier = identifier
    }

    func arrivalAirportChanged() {
        guard let identifier = arrivalAirport?.timeZoneIdentifier else { return }
        arrivalZoneIdentifier = identifier
    }

    // MARK: - Persistence

    /// Creates or updates the flight and saves. Returns the flight on success.
    @discardableResult
    func save(in context: ModelContext) -> Flight? {
        guard canSave, let departureAirport, let arrivalAirport else { return nil }

        let trimmedAirline = airline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNumber = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        // Persist the chosen zone on each airport place so display reflects it.
        var departure = departureAirport
        departure.timeZoneIdentifier = departureZoneIdentifier
        var arrival = arrivalAirport
        arrival.timeZoneIdentifier = arrivalZoneIdentifier

        switch mode {
        case .create(let trip):
            let flight = Flight(
                airline: trimmedAirline,
                flightNumber: trimmedNumber,
                departureAirport: departure,
                arrivalAirport: arrival,
                scheduledDeparture: departureInstant,
                scheduledArrival: arrivalInstant,
                terminal: optional(terminal),
                gate: optional(gate),
                bookingReference: optional(bookingReference),
                seat: optional(seat),
                notes: optional(notes),
                trip: trip
            )
            context.insert(flight)
            try? context.save()
            return flight

        case .edit(let flight):
            flight.airline = trimmedAirline
            flight.flightNumber = trimmedNumber
            flight.departureAirport = departure
            flight.arrivalAirport = arrival
            flight.scheduledDeparture = departureInstant
            flight.scheduledArrival = arrivalInstant
            flight.terminal = optional(terminal)
            flight.gate = optional(gate)
            flight.bookingReference = optional(bookingReference)
            flight.seat = optional(seat)
            flight.notes = optional(notes)
            try? context.save()
            return flight
        }
    }

    // MARK: - Loading

    private func load() {
        switch mode {
        case .create:
            let now = Date()
            departureLocalTime = now
            arrivalLocalTime = now.addingTimeInterval(2 * 3600)
            departureZoneIdentifier = TimeZone.current.identifier
            arrivalZoneIdentifier = TimeZone.current.identifier

        case .edit(let flight):
            airline = flight.airline
            flightNumber = flight.flightNumber
            departureAirport = flight.departureAirport
            arrivalAirport = flight.arrivalAirport
            departureZoneIdentifier = flight.departureTimeZone.identifier
            arrivalZoneIdentifier = flight.arrivalTimeZone.identifier
            // Convert the stored UTC instants into pickable local wall-clock
            // times for the chosen zones.
            departureLocalTime = localTime(from: flight.scheduledDeparture, in: flight.departureTimeZone)
            arrivalLocalTime = localTime(from: flight.scheduledArrival, in: flight.arrivalTimeZone)
        }
    }

    // MARK: - Time-zone conversion helpers

    /// Interprets the wall-clock components of `localWallClock` (which the
    /// picker produced in the device zone) as if they were in `zone`, returning
    /// the corresponding UTC instant.
    private func instant(from localWallClock: Date, in zone: TimeZone) -> Date {
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        let components = deviceCal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: localWallClock
        )
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        return zoneCal.date(from: components) ?? localWallClock
    }

    /// The inverse of `instant(from:in:)`: takes a stored UTC instant and the
    /// zone it should be shown in, and returns a `Date` whose device-zone
    /// wall-clock matches the instant's local wall-clock in `zone`, so the
    /// picker shows the right local time.
    private func localTime(from instant: Date, in zone: TimeZone) -> Date {
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        let components = zoneCal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: instant
        )
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        return deviceCal.date(from: components) ?? instant
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
