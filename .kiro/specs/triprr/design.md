# Design — Triprr

## Overview

Triprr is a single multiplatform SwiftUI app (one target, `triprr`) sharing all models, services and
view models across iPhone and Mac, branching only at the top-level navigation shell. Persistence is
SwiftData. Everything time-sensitive is stored as a UTC `Date` plus a separate IANA time-zone
identifier, and rendered in the relevant place's local zone. All network-touching capabilities
(flight lookup, suggestions, directions/travel time) sit behind protocols with a mock or
MapKit-local implementation shipping first, so the UI never depends on a concrete provider.

This document covers the layered architecture, the SwiftData model graph, the service protocols and
their first implementations, the view-model layer, the navigation structure per platform, the
time-zone strategy, and the testing approach. It maps every section back to the requirements.

### Toolchain decisions (confirmed)

- **Swift 6**: raise `SWIFT_VERSION` from 5.0 to 6.0 for all targets. `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are already set, which keeps UI and view-model
  code on the main actor by default; services that do real async work are explicitly annotated.
- **Deployment**: keep 26.5 for iOS/macOS/xrOS. xrOS keeps building (shared code) but no visionOS-specific UI.
- **Build/test/preview tooling**: Xcode MCP tools against the live Xcode instance (`tabIdentifier
  windowtab1`) — `buildproject`, `xcoderefreshcodeissuesinfile`, `runalltests`/`runsometests`,
  `renderpreview`. Terminal `xcodebuild` is the fallback.
- **macOS sandbox**: add the `com.apple.security.network.client` entitlement so MapKit requests work
  under App Sandbox. Keep `ENABLE_USER_SELECTED_FILES = readonly`.

---

## Architecture

### Layers

```
Views (SwiftUI, platform shells + shared screens)
  │  observe
ViewModels (@Observable, @MainActor; orchestrate services + model context)
  │  call
Services (protocols + implementations: Flight, Suggestion, Routing, Notifications, Geo/TimeZone)
  │  use
Models (SwiftData @Model entities) + Value types (enums, structs, DTOs)
```

- **Models**: SwiftData `@Model` classes and the plain value types (enums, option sets, lightweight
  structs) they reference. No UI, no service calls.
- **Services**: protocols plus concrete implementations. Pure logic (buffer evaluation, suggestion
  time-fitting) lives in testable types that do not touch SwiftData or the UI. Network/MapKit access is
  isolated here behind protocols.
- **ViewModels**: `@Observable @MainActor` types that hold UI state, call services, and read/write the
  `ModelContext`. One per non-trivial screen (trip list, trip dashboard, flight edit, day itinerary,
  suggestions). Simple views bind directly to models without a dedicated view model.
- **Views**: shared SwiftUI screens plus thin platform shells. `#if os(...)` appears only in the
  navigation shell and the handful of places where layout genuinely differs.

### Folder layout (within the `triprr` target)

```
triprr/
  App/            triprrApp.swift, AppContainer (ModelContainer + service wiring), RootView
  Models/         Trip, Destination, Flight, Stay, Booking, Activity, Note, Link, Place, enums
  Services/
    Flight/       FlightLookupService (protocol) + MockFlightLookupService
    Suggestions/  SuggestionService (protocol) + MapKitSuggestionService + SuggestionPlanner (pure)
    Routing/      RoutingService (protocol) + MapKitRoutingService + ScheduleEvaluator (pure)
    Geo/          PlaceSearchService (protocol) + MapKitPlaceSearchService; TimeZoneResolver
    Notifications/ NotificationScheduling (protocol) + LocalNotificationScheduler
  ViewModels/     TripListVM, TripDashboardVM, FlightEditVM, DayItineraryVM, SuggestionsVM, TodayVM
  Views/
    Shell/        RootView, iOS tab/stack shell, macOS NavigationSplitView shell
    Trips/        TripListView, TripDashboardView, TripEditView
    Flights/      FlightListView, FlightEditView, FlightRow
    Stays/        StayEditView, BookingEditView, bookings list
    Itinerary/    DayItineraryView, ActivityEditView, DayMapView, legs/warnings
    Suggestions/  SuggestionsView, SuggestionRow, suggestion input form
    Today/        TodayView
    Common/       EmptyStateView, PlaceSearchField, DatePickers w/ time zone, color/cover pickers
  Support/        SampleData (in-memory previews/tests), Formatters, Date/TimeZone helpers
  Resources/      triprr.entitlements (adds network.client on macOS), Info plist keys
```

The template's `Item.swift` and the demo `ContentView` body are replaced; the file-system-synchronized
group means new files under `triprr/` are picked up automatically.

---

## Data models (SwiftData)

All instants are UTC `Date`. Where local time matters, the owning entity stores an IANA
`timeZoneIdentifier: String` alongside the date. Relationships use SwiftData `@Relationship` with
cascade delete from `Trip` downward (Req 1.4). IDs are SwiftData-managed; we also keep a stable
`UUID` on each entity for notification identifiers and diffing.

### Place (embedded value, not a top-level @Model)

`Place` is stored as a `Codable` struct attribute on entities that have a location, derived from an
`MKMapItem`. Keeping it a value type (not a shared entity) avoids cross-trip aliasing and keeps the
graph simple for the MVP.

```
struct Place: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var timeZoneIdentifier: String?   // resolved via TimeZoneResolver when saved
    // computed: coordinate (CLLocationCoordinate2D), timeZone (TimeZone?)
}
```

### Trip

```
@Model final class Trip {
    var id: UUID
    var name: String
    var startDate: Date            // UTC; a trip day boundary uses the trip's primary time zone
    var endDate: Date
    var coverColorHex: String?     // optional colour cover
    @Attribute(.externalStorage) var coverImageData: Data?   // optional image cover
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Destination.trip) var destinations: [Destination]
    @Relationship(deleteRule: .cascade, inverse: \Flight.trip)      var flights: [Flight]
    @Relationship(deleteRule: .cascade, inverse: \Stay.trip)        var stays: [Stay]
    @Relationship(deleteRule: .cascade, inverse: \Booking.trip)     var bookings: [Booking]
    @Relationship(deleteRule: .cascade, inverse: \Activity.trip)    var activities: [Activity]
    @Relationship(deleteRule: .cascade, inverse: \Note.trip)        var notes: [Note]
    @Relationship(deleteRule: .cascade, inverse: \LinkItem.trip)    var links: [LinkItem]
    // computed: status (upcoming/current/past), primaryTimeZone (first destination's zone or current),
    //           allPlaces (for the dashboard map)
}
```

- **Status** (Req 1.5) is computed from `startDate`/`endDate` vs `now` in the trip's primary time zone.
- **Primary time zone** = first destination place's zone, falling back to the device's current zone.

### Destination

```
@Model final class Destination {
    var id: UUID
    var place: Place
    var sortOrder: Int
    var trip: Trip?
}
```

### Flight (Req 2)

```
@Model final class Flight {
    var id: UUID
    var airline: String
    var flightNumber: String
    var departureAirport: Place          // place carries its own timeZoneIdentifier
    var arrivalAirport: Place
    var scheduledDeparture: Date         // UTC
    var scheduledArrival: Date           // UTC
    var terminal: String?
    var gate: String?
    var bookingReference: String?
    var seat: String?
    var notes: String?
    var trip: Trip?
    // display: departure shown in departureAirport.timeZone, arrival in arrivalAirport.timeZone (Req 2.2)
}
```

### Stay (Req 3)

```
@Model final class Stay {
    var id: UUID
    var name: String
    var kind: StayKind            // hotel | rental
    var place: Place?
    var checkIn: Date             // UTC
    var checkOut: Date
    var timeZoneIdentifier: String?   // place's zone or trip primary
    var confirmationNumber: String?
    var notes: String?
    var trip: Trip?
}
```

### Booking (Req 3 — "other bookings")

```
@Model final class Booking {
    var id: UUID
    var title: String
    var kind: BookingKind         // restaurant | tour | ticket | transport | other
    var place: Place?
    var startDate: Date           // UTC
    var endDate: Date?            // optional range
    var timeZoneIdentifier: String?
    var confirmationNumber: String?
    var notes: String?
    var trip: Trip?
}
```

### Activity (Req 4)

```
@Model final class Activity {
    var id: UUID
    var title: String
    var category: ActivityCategory   // food|museum|outdoors|nightlife|shopping|landmark|transport|other
    var startDate: Date              // UTC
    var endDate: Date?               // time range optional
    var timeZoneIdentifier: String?
    var place: Place?
    var notes: String?
    var isDone: Bool
    var sortOrder: Int               // tiebreak for reordering within a time (Req 4.3)
    var travelModeRaw: String?       // optional per-activity override of travel mode to reach it
    var trip: Trip?
    @Relationship(deleteRule: .cascade, inverse: \Note.activity) var notes2: [Note]   // activity notes
    @Relationship(deleteRule: .cascade, inverse: \LinkItem.activity) var links: [LinkItem]
}
```

### Note / LinkItem (Req 6)

Each belongs to either a `Trip` or an `Activity` (both optional; exactly one set).

```
@Model final class Note { var id: UUID; var text: String; var createdAt: Date; var trip: Trip?; var activity: Activity? }
@Model final class LinkItem { var id: UUID; var title: String; var urlString: String; var trip: Trip?; var activity: Activity? }
```

### Enums & value types

`StayKind`, `BookingKind`, `ActivityCategory`, `TripStatus`, `TravelMode` (automobile/walking/transit),
`Pace` (relaxed/packed), `Interest` (food/museums/outdoors/nightlife/shopping/landmarks). All `Codable`
+ `CaseIterable` where useful, with SF Symbol + display name helpers for the UI.

### Timeline unification

The itinerary and timeline need flights, stays, bookings and activities as one ordered list. A value
type `TimelineEntry` wraps each with a common interface (title, start instant, end instant, time zone,
place, SF Symbol, source reference) so day views and the Today screen sort and render them uniformly
(Req 4.1, 7.1) without a shared superclass.

### Schema versioning

Wrap the schema in a `SchemaV1` / `TriprrMigrationPlan` from the start so future entities (the
out-of-scope list) can be added via lightweight migration without data loss. MVP ships V1 only.

---

## Services

Every service is a protocol in the `Services` layer. Concrete types are injected into view models via
an `AppServices` container built in `triprrApp` and passed through the SwiftUI environment, so previews
and tests substitute mocks freely.

### TimeZoneResolver (Req 10.2, 10.3)

Not networked. Resolves an IANA time zone for a coordinate using `CLGeocoder` reverse geocoding when
online, caching the result on the `Place`. Offline or on failure it falls back to the trip's primary
zone or the device zone, and the UI still renders with whatever zone is stored. This keeps time-zone
display correct without blocking saves.

### PlaceSearchService (Req 1.8, 4.2) — MapKit

```
protocol PlaceSearchService: Sendable {
    func search(query: String, region: MKCoordinateRegion?) async throws -> [Place]
}
```

First implementation `MapKitPlaceSearchService` uses `MKLocalSearch`. Powers the `PlaceSearchField`
used in trip destinations, activities, stays and bookings.

### FlightLookupService (Req 2.4, 2.5)

```
struct FlightLookupQuery { let flightNumber: String; let date: Date }
struct FlightLookupResult { airline, flightNumber, departureAirport: Place, arrivalAirport: Place,
                            scheduledDeparture: Date, scheduledArrival: Date, terminal/gate: String? }
protocol FlightLookupService: Sendable {
    func lookup(_ query: FlightLookupQuery) async throws -> FlightLookupResult
}
```

Ships `MockFlightLookupService`: returns plausible deterministic data (recognises a few sample flight
numbers, otherwise synthesises a result) and can be configured to throw to exercise the error path
(Req 2.5). A `// TODO: real provider` seam documents where an API-backed implementation plugs in — no
UI change required because the UI only knows the protocol.

### RoutingService (Req 4.4–4.6) — MapKit

```
struct TravelEstimate { let travelTime: TimeInterval; let distance: CLLocationDistance; let mode: TravelMode }
protocol RoutingService: Sendable {
    func estimate(from: Place, to: Place, mode: TravelMode) async throws -> TravelEstimate
    func appleMapsRouteURL(stops: [Place], mode: TravelMode) -> URL?   // opens Apple Maps (Req 4.7)
}
```

`MapKitRoutingService` uses `MKDirections.calculate(completionHandler:)` wrapped in async, with a short
in-memory cache keyed by (from, to, mode) to avoid recomputing legs on every redraw. On failure/offline
it throws a typed `RoutingError.unavailable`; the day view catches it and renders the leg as
"travel estimate unavailable" (Req 4.6).

### ScheduleEvaluator (pure — Req 4.5)

A plain, fully testable type (no MapKit, no SwiftData). Given an ordered list of entries with
start/end instants and the travel estimates between consecutive placed entries, plus a configurable
`buffer: TimeInterval`, it returns per-gap results:

```
enum GapStatus { case ok, tight(shortfall: TimeInterval), overlap }
struct ScheduleWarning { let afterEntryID: UUID; let status: GapStatus; let requiredTravel: TimeInterval? }
func evaluate(entries: [TimelineEntry], estimates: [LegKey: TravelEstimate], buffer: TimeInterval) -> [ScheduleWarning]
```

Rule: a gap is `tight` when `nextStart - prevEnd < travelTime + buffer`, and `overlap` when the next
item starts before the previous ends. The flight case (Req 4.5) treats "before a flight" as a leg into
the departure airport. This is the primary unit-tested logic.

### SuggestionService + SuggestionPlanner (Req 5)

```
struct SuggestionRequest {
    var area: Place                     // city/area, defaults from trip/day
    var start: Date                     // UTC
    var available: TimeInterval         // 4h / half-day / full-day / custom
    var interests: [Interest]
    var pace: Pace
}
struct Suggestion: Identifiable {
    let id: UUID; let place: Place; let category: ActivityCategory
    let summary: String; let estimatedVisitDuration: TimeInterval
    let distanceFromPrevious: CLLocationDistance?; let arrivalTime: Date; let departureTime: Date
}
protocol SuggestionService: Sendable {
    func suggestions(for request: SuggestionRequest) async throws -> [Suggestion]
}
```

`MapKitSuggestionService` composes:
1. **Discovery** — `MKLocalSearch` queries derived from the chosen interests (mapped to MapKit point-of-
   interest categories; defaults to a landmark/food mix when none chosen), scoped to the area's region.
2. **Planning** — the pure `SuggestionPlanner` performs the time-fitting (below), calling `RoutingService`
   for inter-stop travel so travel time is realistic (Req 5.3).

`SuggestionPlanner` (pure, testable): greedily/with simple scoring selects candidates so the running
total of `visitDuration(category, pace) + travelTime(previous→candidate)` stays within `available`
starting at `start`, respecting opening hours when a candidate exposes them (skip or defer a closed
place), and stops when time runs out. Per-category visit durations are fixed, tunable constants
(e.g. museum ~90m, landmark ~45m, meal ~75m, outdoors ~60m), scaled by pace (packed shortens, relaxed
lengthens). It assigns each selected suggestion an `arrivalTime`/`departureTime`. Travel estimates are
injected so the planner itself needs no MapKit and is unit-tested directly (Req 11.4).

Empty vs error states (Req 5.6) are distinct: zero candidates → empty state; a thrown error or offline
→ error state, surfaced by `SuggestionsVM`.

### NotificationScheduling (Req 8)

```
protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> Bool
    func reschedule(for trip: Trip, leadTime: TimeInterval) async
    func cancel(ids: [UUID]) async
}
```

`LocalNotificationScheduler` wraps `UNUserNotificationCenter`, scheduling notifications a configurable
lead time before flights and timed activities using `UNCalendarNotificationTrigger` in the item's local
zone. Denial disables the feature silently; the rest of the app is unaffected (Req 8.1, 8.4). Called by
view models after create/edit/delete so triggers stay in sync (Req 8.3).

---

## ViewModels

All `@Observable @MainActor`. They receive `AppServices` and a `ModelContext`.

- **TripListVM** — fetches trips, computes Upcoming/Current/Past grouping and sorting (Req 1.5), create/
  delete with confirmation (Req 1.4).
- **TripDashboardVM** — countdown/status, assembles the dashboard map region from `trip.allPlaces`,
  exposes section shortcuts (Req 1.7).
- **FlightEditVM** — manual entry + "look up" action calling `FlightLookupService`, mapping result into
  the form, handling the error/offline path (Req 2.4, 2.5).
- **DayItineraryVM** — builds the ordered `TimelineEntry` list for a day, requests travel estimates from
  `RoutingService`, runs `ScheduleEvaluator` for warnings, exposes reorder/add/remove, and builds the
  Apple Maps route URL (Req 4).
- **SuggestionsVM** — holds the request form, calls `SuggestionService`, manages loading/empty/error
  states, and performs one-tap "add to day" by creating an `Activity` (Req 5.5, 5.6).
- **TodayVM** — picks the active trip/day, highlights current/next item in the day's local zone (Req 7).

---

## Navigation structure

A shared `RootView` branches once:

```
RootView
#if os(macOS)  → NavigationSplitView { TripSidebar } detail: { TripDetail (dashboard + sections) }
#else (iOS)    → TabView { TripsTab (NavigationStack: list → dashboard → sections), TodayTab }
#endif
```

- **Mac** (Req 9.1): sidebar lists trips grouped by status; selecting a trip fills the detail area with
  its dashboard; sections (Flights/Stays/Itinerary/Suggestions/Today) are presented within the detail,
  using a secondary split or segmented layout where it reads better on the larger canvas.
- **iPhone** (Req 9.2): a tab bar (Trips, Today) with a `NavigationStack` under Trips: list → dashboard
  → each section → edit sheets. Same hierarchy, same view models.

Shared screens (dashboard, flight/stay/booking/activity editors, day itinerary, suggestions, Today) are
platform-agnostic; only the two shells and a few layout spots use `#if os(...)` (Req 9.3). Dark Mode and
Dynamic Type come free from using semantic colors, SF Symbols and standard text styles, and are checked
via previews (Req 9.4–9.6).

---

## Time-zone strategy (Req 10.2, 10.3)

- Store every instant as a UTC `Date`.
- Store an IANA identifier where local time matters: on `Place` (airports, activity/stay/booking
  locations) and as a per-entity fallback field.
- A `TimeZoneResolver` fills `Place.timeZoneIdentifier` via reverse geocoding when a place is saved;
  offline it defers to the trip primary / device zone and can backfill later.
- Display helpers format a `Date` in a given `TimeZone` with a visible zone label (e.g. "09:30 JST").
- "Today"/countdown/day boundaries are computed in the relevant place's zone, not the device's, so a
  trip abroad shows the correct local day (Req 7.3).

Edge cases covered by tests: DST transitions, a flight crossing midnight or the date line (arrival local
time earlier than departure local time), and day-bucketing an instant that falls on different calendar
days in different zones.

---

## Error handling & offline (Req 10.4, 10.5)

- Saved data is always viewable/editable offline (pure SwiftData reads/writes).
- Networked services throw typed errors; view models translate them into explicit UI states:
  flight-lookup error (manual entry still available), routing-unavailable (itinerary degrades per leg),
  suggestions empty vs error/offline. No network failure ever discards or corrupts stored data.
- Reverse geocoding failures are non-fatal (fallback zone).

---

## Testing (Swift Testing — Req 11.4)

Unit tests target the pure, logic-heavy types so they run fast with no simulator UI or live network:

1. **Date/time-zone logic**: UTC storage round-trips; display formatting in a target zone; day-bucketing
   across zones; DST and date-line flight cases.
2. **ScheduleEvaluator**: ok / tight / overlap gaps against fixed estimates and buffers; the before-a-
   flight leg; missing-estimate legs produce no false warning.
3. **SuggestionPlanner**: fits within available time; respects pace scaling and per-category durations;
   accounts for injected travel times; skips closed places; empty when nothing fits.

Services that wrap MapKit/UN frameworks are kept thin so the planner/evaluator can be tested with
injected estimates and mock candidates. `SampleData` provides in-memory `ModelContainer` fixtures reused
by both previews and tests. Builds are verified for iOS and macOS with zero warnings under Swift 6
(Req 11.3) after each task.

---

## Requirements coverage map

| Requirement | Where addressed |
|---|---|
| 1 Trips | `Trip`/`Destination` models, `TripListVM`, `TripDashboardVM`, trip views, status/countdown, cascade delete |
| 2 Flights | `Flight` model, `FlightLookupService` + mock, `FlightEditVM`, per-airport zone display |
| 3 Stays/bookings | `Stay`/`Booking` models, editors, itinerary placement |
| 4 Itinerary | `Activity`, `TimelineEntry`, `RoutingService`, `ScheduleEvaluator`, `DayItineraryVM`, `DayMapView`, Apple Maps URL |
| 5 Suggestions | `SuggestionService` + `MapKitSuggestionService` + pure `SuggestionPlanner`, `SuggestionsVM`, empty/error states |
| 6 Notes/links | `Note`/`LinkItem` models + detail UI |
| 7 Today | `TodayVM`, `TodayView`, local-zone "now" |
| 8 Notifications | `NotificationScheduling` + `LocalNotificationScheduler` |
| 9 Platform UX | `RootView` shells, shared screens, Dark Mode/Dynamic Type, previews |
| 10 Persistence/TZ/offline | SwiftData container, UTC+IANA strategy, `TimeZoneResolver`, typed offline states |
| 11 Architecture/quality/build | layer separation, protocol-first services, Swift 6 clean build, Swift Testing, task ordering |
