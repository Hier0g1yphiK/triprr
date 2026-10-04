# Triprr

Triprr is a native travel itinerary app for iPhone and Mac, built with Swift 6 and SwiftUI from a single multiplatform target. It gathers everything about a trip in one place — flights, stays, day-by-day plans, and ideas for what to do — and works fully offline once data is saved.

Its standout capability is suggesting things to do in a city that realistically fit the amount of time you have there, using Apple's MapKit so no paid third-party API or key is required for the core app.

## Features

- **Trips** — Create and manage trips with dates, destinations, and a cover colour or image. Trips are grouped into Upcoming, Current, and Past, with a dashboard showing a live countdown and a map of the trip's places.
- **Flights** — Record airline, flight number, airports, and scheduled times. Times display in the local time zone of the relevant airport. A `FlightLookupService` seam lets a real provider replace the shipping mock without any UI change.
- **Stays & bookings** — Track hotels and rentals (check-in/check-out) plus other reservations (restaurants, tours, tickets, transport), each surfaced on the right day of the itinerary.
- **Daily itinerary** — A day-by-day plan listing every item in time order, with MapKit-estimated travel times between placed items and warnings when the gap is too tight for your configurable buffer. Includes a day map view that opens the route in Apple Maps.
- **Smart suggestions** — The key feature: suggestions for what to do that fit the time you have, accounting for realistic travel time, per-category visit duration, pace, and opening hours. Add any suggestion to a day's itinerary in one tap.
- **Notes & links** — Attach notes and tappable links to a trip or an activity so reference material stays with the thing it relates to.
- **Today screen** — See the current day's items at a glance with the current/next item highlighted, using the local time zone of the day's place.
- **Local notifications** — Timely reminders for upcoming items.

## Architecture

- **UI:** SwiftUI, multiplatform (iOS, macOS, xrOS).
- **Persistence:** SwiftData, with a versioned schema and migration plan. Instants are stored in UTC and displayed in the local time zone of the place involved.
- **Services:** Anything that could rely on an external provider (flight lookup, place search, routing, suggestions, notifications) sits behind a protocol in the `Services` layer. Concrete implementations are injected through `AppServices` and passed via the SwiftUI environment, so previews and tests can substitute mocks without touching the views. MapKit-backed and mock implementations ship first.
- **Offline-first:** Core functionality works without a network once data is saved.

### Project layout

```
triprr/
  App/            App entry point and the AppServices dependency container
  Models/         SwiftData models, enums, and the versioned schema
  Services/       Protocol-defined services (Flight, Geo, Routing, Schedule, Suggestions, Notifications)
  ViewModels/     View models for the main screens
  Views/          SwiftUI views, grouped by feature
  Support/        Helpers (date, colour, sample data)
triprrTests/      Unit tests (Swift Testing)
triprrUITests/    UI tests
```

## Requirements

- Xcode 26.6 or later
- Swift 6
- Deployment target 26.5 (iOS, macOS, xrOS)

## Getting started

1. Clone the repository.
2. Open `triprr.xcodeproj` in Xcode.
3. Select the `triprr` scheme and a simulator or device.
4. Build and run (⌘R).

The macOS target runs in the App Sandbox and uses a network entitlement for MapKit requests.

## Testing

Run the test suites from Xcode (⌘U) or from the command line:

```sh
xcodebuild test -project triprr.xcodeproj -scheme triprr \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Status

MVP in progress. Out of scope for this release (but accounted for in the data model): accounts, cloud sync, collaboration/sharing, email parsing, expense tracking, document storage, Apple Watch, and widgets.
