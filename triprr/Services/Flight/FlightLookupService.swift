//
//  FlightLookupService.swift
//  triprr
//
//  Protocol + mock implementation for looking up flight details by flight
//  number and date. Powers the "look up" action in the flight editor so the
//  user can autofill the form instead of typing everything manually (Req 2.4).
//  Behind a protocol so previews/tests substitute a mock and a real API-backed
//  provider can be swapped in later without changing the UI. When a lookup
//  fails or the device is offline the editor keeps full manual entry (Req 2.5).
//

import Foundation

/// The input to a flight lookup: a flight number and the date it operates on.
nonisolated struct FlightLookupQuery: Equatable, Sendable {
    var flightNumber: String
    var date: Date

    init(flightNumber: String, date: Date) {
        self.flightNumber = flightNumber
        self.date = date
    }
}

/// The details returned for a looked-up flight. Airports are `Place` values so
/// they carry their own coordinate and time zone for correct local-time
/// display; the editor maps these straight into its form.
nonisolated struct FlightLookupResult: Equatable, Sendable {
    var airline: String
    var flightNumber: String
    var departureAirport: Place
    var arrivalAirport: Place
    /// UTC instant; displayed in `departureAirport`'s zone.
    var scheduledDeparture: Date
    /// UTC instant; displayed in `arrivalAirport`'s zone.
    var scheduledArrival: Date
    var terminal: String?
    var gate: String?
}

/// Errors a flight lookup can surface. The editor translates these into a
/// clear message while keeping manual entry available (Req 2.5).
nonisolated enum FlightLookupError: Error, Equatable {
    /// No network connection.
    case offline
    /// The flight could not be found for the given number/date.
    case notFound
    /// The lookup failed for another reason.
    case failed
}

extension FlightLookupError {
    /// A short, user-facing explanation suitable for the editor.
    var message: String {
        switch self {
        case .offline:
            "You appear to be offline. Enter the flight details manually, or try again when connected."
        case .notFound:
            "Couldn't find that flight. Check the number and date, or enter the details manually."
        case .failed:
            "The flight lookup failed. Enter the details manually, or try again."
        }
    }
}

/// Looks up flight details for a flight number on a given date.
///
/// Networked implementations throw `FlightLookupError`; the UI depends only on
/// this protocol so the concrete provider can change freely.
nonisolated protocol FlightLookupService: Sendable {
    func lookup(_ query: FlightLookupQuery) async throws -> FlightLookupResult
}

// TODO: real provider — add an API-backed `FlightLookupService` here (e.g. a
// scheduled-flights API). It only needs to satisfy this protocol and throw
// `FlightLookupError` on failure; no UI change is required because the editor
// talks to the protocol, not a concrete type.

/// A deterministic mock for the running app, previews and tests. Recognises a
/// few sample flight numbers and otherwise synthesises a plausible result, so
/// the lookup action always produces something to populate the form without
/// touching the network. Can be configured to throw to exercise the
/// error/offline path (Req 2.5).
nonisolated struct MockFlightLookupService: FlightLookupService {
    /// When set, every lookup throws this error (to exercise the error path).
    var errorToThrow: FlightLookupError?
    /// Simulated latency so previews/tests can see the loading state.
    var delay: Duration

    init(errorToThrow: FlightLookupError? = nil, delay: Duration = .zero) {
        self.errorToThrow = errorToThrow
        self.delay = delay
    }

    func lookup(_ query: FlightLookupQuery) async throws -> FlightLookupResult {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let errorToThrow { throw errorToThrow }

        let number = query.flightNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !number.isEmpty else { throw FlightLookupError.notFound }

        if let sample = Self.sampleFlights[number] {
            return sample.result(on: query.date)
        }
        return Self.synthesised(number: number, on: query.date)
    }

    // MARK: - Sample flights

    /// A plausible scheduled flight, stored as local wall-clock components in
    /// each airport's zone so the result lands at sensible local times on
    /// whatever date the user asks about.
    private struct SampleFlight {
        var airline: String
        var number: String
        var departure: Place
        var arrival: Place
        /// Local departure hour/minute in the departure airport's zone.
        var departureLocal: (hour: Int, minute: Int)
        /// Flight duration.
        var duration: Duration
        var terminal: String?
        var gate: String?

        func result(on date: Date) -> FlightLookupResult {
            let departureZone = departure.timeZone ?? .current
            let scheduledDeparture = MockFlightLookupService.instant(
                on: date,
                hour: departureLocal.hour,
                minute: departureLocal.minute,
                in: departureZone
            )
            let scheduledArrival = scheduledDeparture.addingTimeInterval(
                TimeInterval(duration.components.seconds)
            )
            return FlightLookupResult(
                airline: airline,
                flightNumber: number,
                departureAirport: departure,
                arrivalAirport: arrival,
                scheduledDeparture: scheduledDeparture,
                scheduledArrival: scheduledArrival,
                terminal: terminal,
                gate: gate
            )
        }
    }

    private static let sampleFlights: [String: SampleFlight] = [
        "BA005": SampleFlight(
            airline: "British Airways",
            number: "BA005",
            departure: Place(
                name: "London Heathrow (LHR)",
                latitude: 51.4700, longitude: -0.4543,
                address: "Longford, UK",
                timeZoneIdentifier: "Europe/London"
            ),
            arrival: Place(
                name: "Tokyo Haneda (HND)",
                latitude: 35.5494, longitude: 139.7798,
                address: "Ota City, Tokyo, Japan",
                timeZoneIdentifier: "Asia/Tokyo"
            ),
            departureLocal: (hour: 11, minute: 30),
            duration: .seconds(14 * 3600),
            terminal: "5",
            gate: "A12"
        ),
        "AA100": SampleFlight(
            airline: "American Airlines",
            number: "AA100",
            departure: Place(
                name: "New York JFK (JFK)",
                latitude: 40.6413, longitude: -73.7781,
                address: "Queens, NY, USA",
                timeZoneIdentifier: "America/New_York"
            ),
            arrival: Place(
                name: "London Heathrow (LHR)",
                latitude: 51.4700, longitude: -0.4543,
                address: "Longford, UK",
                timeZoneIdentifier: "Europe/London"
            ),
            departureLocal: (hour: 18, minute: 30),
            duration: .seconds(7 * 3600),
            terminal: "8",
            gate: "C3"
        ),
        "AF1680": SampleFlight(
            airline: "Air France",
            number: "AF1680",
            departure: Place(
                name: "Paris Charles de Gaulle (CDG)",
                latitude: 49.0097, longitude: 2.5479,
                address: "Roissy-en-France, France",
                timeZoneIdentifier: "Europe/Paris"
            ),
            arrival: Place(
                name: "London Heathrow (LHR)",
                latitude: 51.4700, longitude: -0.4543,
                address: "Longford, UK",
                timeZoneIdentifier: "Europe/London"
            ),
            departureLocal: (hour: 9, minute: 15),
            duration: .seconds(80 * 60),
            terminal: "2E",
            gate: nil
        ),
    ]

    // MARK: - Synthesis

    /// Builds a plausible result for an unknown flight number so the lookup
    /// always returns something. Uses a generic airline name derived from the
    /// number's prefix and a mid-haul domestic-looking pairing.
    private static func synthesised(number: String, on date: Date) -> FlightLookupResult {
        let airlinePrefix = String(number.prefix { $0.isLetter })
        let airline = airlinePrefix.isEmpty ? "Airline" : "\(airlinePrefix) Airlines"

        let departure = Place(
            name: "San Francisco (SFO)",
            latitude: 37.6213, longitude: -122.3790,
            address: "San Francisco, CA, USA",
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let arrival = Place(
            name: "Seattle (SEA)",
            latitude: 47.4502, longitude: -122.3088,
            address: "Seattle, WA, USA",
            timeZoneIdentifier: "America/Los_Angeles"
        )
        let departureZone = departure.timeZone ?? .current
        let scheduledDeparture = instant(on: date, hour: 10, minute: 0, in: departureZone)
        let scheduledArrival = scheduledDeparture.addingTimeInterval(2 * 3600)

        return FlightLookupResult(
            airline: airline,
            flightNumber: number,
            departureAirport: departure,
            arrivalAirport: arrival,
            scheduledDeparture: scheduledDeparture,
            scheduledArrival: scheduledArrival,
            terminal: nil,
            gate: nil
        )
    }

    /// The UTC instant for `hour:minute` local time in `zone` on the calendar
    /// day of `date` (evaluated in `zone`).
    private static func instant(on date: Date, hour: Int, minute: Int, in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let day = cal.startOfDay(for: date)
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? date
    }
}
