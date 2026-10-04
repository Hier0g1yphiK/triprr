//
//  SampleData.swift
//  triprr
//
//  In-memory sample data for SwiftUI previews and unit tests. Builds a
//  ModelContainer seeded with representative trips so views have real content
//  to render and tests have fixtures to exercise.
//

import Foundation
import SwiftData

/// Factory for in-memory sample containers and fixture objects.
@MainActor
enum SampleData {
    /// A shared in-memory container seeded with sample trips. Suitable for
    /// previews (`.modelContainer(SampleData.container)`).
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: true
        )
        do {
            let container = try ModelContainer(
                for: currentSchema,
                configurations: [configuration]
            )
            seed(into: container.mainContext)
            return container
        } catch {
            fatalError("Could not create sample ModelContainer: \(error)")
        }
    }()

    /// An empty in-memory container, for empty-state previews and tests.
    static func emptyContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: true
        )
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: currentSchema, configurations: [configuration])
    }

    // MARK: - Seeding

    /// Inserts sample trips into the given context.
    static func seed(into context: ModelContext) {
        for trip in makeSampleTrips() {
            context.insert(trip)
        }
        try? context.save()
    }

    /// Builds the sample trips graph without inserting it.
    static func makeSampleTrips() -> [Trip] {
        [makeTokyoTrip(), makeUpcomingParisTrip(), makePastTrip()]
    }

    // MARK: - Fixture places

    static let heathrow = Place(
        name: "London Heathrow (LHR)",
        latitude: 51.4700, longitude: -0.4543,
        address: "Longford, UK",
        timeZoneIdentifier: "Europe/London"
    )
    static let haneda = Place(
        name: "Tokyo Haneda (HND)",
        latitude: 35.5494, longitude: 139.7798,
        address: "Ota City, Tokyo, Japan",
        timeZoneIdentifier: "Asia/Tokyo"
    )
    static let tokyoStation = Place(
        name: "Tokyo Station Hotel",
        latitude: 35.6812, longitude: 139.7671,
        address: "1 Chome Marunouchi, Chiyoda City, Tokyo",
        timeZoneIdentifier: "Asia/Tokyo"
    )
    static let sensoji = Place(
        name: "Sensō-ji",
        latitude: 35.7148, longitude: 139.7967,
        address: "2 Chome-3-1 Asakusa, Taito City, Tokyo",
        timeZoneIdentifier: "Asia/Tokyo"
    )
    static let teamLab = Place(
        name: "teamLab Planets",
        latitude: 35.6487, longitude: 139.7905,
        address: "6 Chome-1-16 Toyosu, Koto City, Tokyo",
        timeZoneIdentifier: "Asia/Tokyo"
    )
    static let sushiRestaurant = Place(
        name: "Sushi Dai",
        latitude: 35.6494, longitude: 139.7861,
        address: "Toyosu Market, Koto City, Tokyo",
        timeZoneIdentifier: "Asia/Tokyo"
    )
    static let eiffelTower = Place(
        name: "Eiffel Tower",
        latitude: 48.8584, longitude: 2.2945,
        address: "Champ de Mars, Paris, France",
        timeZoneIdentifier: "Europe/Paris"
    )

    // MARK: - Trip builders

    /// A trip that is "current" (brackets today) to Tokyo, with a flight,
    /// a stay, a booking and activities across time zones.
    static func makeTokyoTrip() -> Trip {
        let tokyoZone = TimeZone(identifier: "Asia/Tokyo")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyoZone

        let now = Date()
        let start = cal.date(byAdding: .day, value: -1, to: now)!
        let end = cal.date(byAdding: .day, value: 5, to: now)!

        let trip = Trip(
            name: "Tokyo Adventure",
            startDate: cal.startOfDay(for: start),
            endDate: cal.startOfDay(for: end),
            coverColorHex: "#E4572E"
        )
        trip.destinations = [Destination(place: tokyoStation, sortOrder: 0, trip: trip)]

        // Outbound flight LHR -> HND. Departs London morning, arrives Tokyo
        // the next local day (crosses zones), demonstrating per-airport zones.
        let londonZone = TimeZone(identifier: "Europe/London")!
        var londonCal = Calendar(identifier: .gregorian)
        londonCal.timeZone = londonZone
        let depComponents = DateComponents(
            timeZone: londonZone,
            year: londonCal.component(.year, from: start),
            month: londonCal.component(.month, from: start),
            day: londonCal.component(.day, from: start),
            hour: 11, minute: 30
        )
        let departure = londonCal.date(from: depComponents) ?? start
        // ~14h flight.
        let arrival = departure.addingTimeInterval(14 * 3600)

        trip.flights = [
            Flight(
                airline: "British Airways",
                flightNumber: "BA005",
                departureAirport: heathrow,
                arrivalAirport: haneda,
                scheduledDeparture: departure,
                scheduledArrival: arrival,
                terminal: "5",
                gate: "A12",
                bookingReference: "X7K2PQ",
                seat: "32A",
                notes: "Window seat, meal preordered.",
                trip: trip
            )
        ]

        trip.stays = [
            Stay(
                name: "The Tokyo Station Hotel",
                kind: .hotel,
                place: tokyoStation,
                checkIn: arrival.addingTimeInterval(2 * 3600),
                checkOut: cal.startOfDay(for: end).addingTimeInterval(11 * 3600),
                timeZoneIdentifier: "Asia/Tokyo",
                confirmationNumber: "TSH-99381",
                notes: "City-side room.",
                trip: trip
            )
        ]

        // A day of activities in Tokyo local time (the day after arrival).
        let dayBase = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: arrival)!)
        func tokyoTime(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: dayBase)!
        }

        trip.activities = [
            Activity(
                title: "Breakfast at Toyosu",
                category: .food,
                startDate: tokyoTime(8),
                endDate: tokyoTime(9),
                timeZoneIdentifier: "Asia/Tokyo",
                place: sushiRestaurant,
                notes: "Freshest sushi in the city.",
                sortOrder: 0,
                trip: trip
            ),
            Activity(
                title: "teamLab Planets",
                category: .museum,
                startDate: tokyoTime(10),
                endDate: tokyoTime(12),
                timeZoneIdentifier: "Asia/Tokyo",
                place: teamLab,
                sortOrder: 1,
                trip: trip
            ),
            Activity(
                title: "Sensō-ji Temple",
                category: .landmark,
                startDate: tokyoTime(14),
                endDate: tokyoTime(15, 30),
                timeZoneIdentifier: "Asia/Tokyo",
                place: sensoji,
                sortOrder: 2,
                trip: trip
            ),
        ]

        trip.bookings = [
            Booking(
                title: "Robot Restaurant Show",
                kind: .ticket,
                place: nil,
                startDate: tokyoTime(19),
                endDate: tokyoTime(20, 30),
                timeZoneIdentifier: "Asia/Tokyo",
                confirmationNumber: "RR-55012",
                trip: trip
            )
        ]

        trip.notes = [Note(text: "Pick up a Suica card at the airport.", trip: trip)]
        trip.links = [
            LinkItem(
                title: "Tokyo Metro map",
                urlString: "https://www.tokyometro.jp/en/subwaymap/",
                trip: trip
            )
        ]

        return trip
    }

    /// An upcoming trip to Paris with just destinations, for list/empty-ish states.
    static func makeUpcomingParisTrip() -> Trip {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris")!
        let start = cal.date(byAdding: .day, value: 40, to: Date())!
        let end = cal.date(byAdding: .day, value: 45, to: Date())!

        let trip = Trip(
            name: "Paris in Spring",
            startDate: cal.startOfDay(for: start),
            endDate: cal.startOfDay(for: end),
            coverColorHex: "#4A90D9"
        )
        trip.destinations = [
            Destination(
                place: Place(
                    name: "Paris",
                    latitude: 48.8566, longitude: 2.3522,
                    address: "Paris, France",
                    timeZoneIdentifier: "Europe/Paris"
                ),
                sortOrder: 0,
                trip: trip
            )
        ]
        trip.activities = [
            Activity(
                title: "Eiffel Tower",
                category: .landmark,
                startDate: cal.date(bySettingHour: 10, minute: 0, second: 0, of: start)!,
                timeZoneIdentifier: "Europe/Paris",
                place: eiffelTower,
                trip: trip
            )
        ]
        return trip
    }

    /// A past trip for the "Past" grouping.
    static func makePastTrip() -> Trip {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let start = cal.date(byAdding: .day, value: -120, to: Date())!
        let end = cal.date(byAdding: .day, value: -113, to: Date())!
        let trip = Trip(
            name: "New York Weekend",
            startDate: cal.startOfDay(for: start),
            endDate: cal.startOfDay(for: end),
            coverColorHex: "#7B4FA3"
        )
        trip.destinations = [
            Destination(
                place: Place(
                    name: "New York City",
                    latitude: 40.7128, longitude: -74.0060,
                    address: "New York, NY, USA",
                    timeZoneIdentifier: "America/New_York"
                ),
                sortOrder: 0,
                trip: trip
            )
        ]
        return trip
    }

    /// The sample "current" trip, for detail/dashboard previews.
    static func currentTrip(in context: ModelContext) -> Trip {
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.name == "Tokyo Adventure" }
        )
        return (try? context.fetch(descriptor).first) ?? makeTokyoTrip()
    }
}
