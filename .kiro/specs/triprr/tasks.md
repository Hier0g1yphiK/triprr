# Implementation Plan — Triprr

Each task leaves the app building cleanly for iOS and macOS (Swift 6, zero warnings) and runnable.
Build/diagnostics/tests/previews are driven through the Xcode MCP tools against the live Xcode
instance (`tabIdentifier windowtab1`); terminal `xcodebuild` is the fallback. Sub-tasks reference the
requirements they satisfy. Tasks are ordered: foundation → trips → flights → stays/bookings →
itinerary → suggestions → extras → polish.

- [x] 1. Foundation: Swift 6, entitlements, project skeleton
  - [x] 1.1 Raise `SWIFT_VERSION` to 6.0 for all targets; build and resolve any template concurrency errors; confirm zero warnings on iOS and macOS.
    - _Requirements: 11.3_
  - [x] 1.2 Add `triprr.entitlements` with `com.apple.security.network.client` and wire it into the macOS build settings; add required Info.plist usage keys (location-when-in-use for place/zone resolution, user notifications).
    - _Requirements: 10.5, 8.1_
  - [x] 1.3 Create the folder structure (App/Models/Services/ViewModels/Views/Support/Resources) and an `AppServices` container; replace the demo `ContentView` with a placeholder `RootView` so the app still launches.
    - _Requirements: 11.1_

- [x] 2. Models & persistence
  - [x] 2.1 Add value types/enums: `Place`, `StayKind`, `BookingKind`, `ActivityCategory`, `TripStatus`, `TravelMode`, `Pace`, `Interest` with SF Symbol + display-name helpers.
    - _Requirements: 10.2, 11.1_
  - [x] 2.2 Add SwiftData models: `Trip`, `Destination`, `Flight`, `Stay`, `Booking`, `Activity`, `Note`, `LinkItem` with cascade relationships from `Trip`.
    - _Requirements: 1.1, 1.4, 2.1, 3.1, 3.2, 4.2, 6.1, 10.1_
  - [x] 2.3 Wrap the schema in `SchemaV1` + `TriprrMigrationPlan`; update `triprrApp` to build the `ModelContainer` from it; remove `Item.swift`.
    - _Requirements: 10.1_
  - [x] 2.4 Add `SampleData` providing an in-memory `ModelContainer` with representative trips/flights/stays/bookings/activities for previews and tests.
    - _Requirements: 9.6_
  - [x] 2.5 Add date/time-zone helpers (UTC storage, format-in-zone with label, day-bucketing in a zone) and `TimelineEntry` unification type.
    - _Requirements: 10.2, 10.3, 4.1_
  - [x] 2.6 Write Swift Testing tests for date/time-zone logic (UTC round-trip, format-in-zone, day-bucketing across zones, DST, date-line flight). Build + run tests green.
    - _Requirements: 11.4, 10.2, 10.3_

- [x] 3. Navigation shell & trips
  - [x] 3.1 Build `RootView` shells: macOS `NavigationSplitView` (sidebar + detail), iOS `TabView` + `NavigationStack`; share one trip hierarchy.
    - _Requirements: 9.1, 9.2, 9.3_
  - [x] 3.2 `TripListVM` + `TripListView`: fetch trips, group Upcoming/Current/Past, sort, empty state.
    - _Requirements: 1.5, 1.6_
  - [x] 3.3 `TripEditView`: create/edit with name, start/end dates (end-before-start validation), destinations via `PlaceSearchField`, colour/image cover.
    - _Requirements: 1.1, 1.2, 1.8_
  - [x] 3.4 Delete trips with confirmation when non-empty; verify cascade delete.
    - _Requirements: 1.3, 1.4_
  - [x] 3.5 `PlaceSearchService` protocol + `MapKitPlaceSearchService` + reusable `PlaceSearchField`; `TimeZoneResolver` to backfill `Place.timeZoneIdentifier`.
    - _Requirements: 1.8, 4.2, 10.2, 10.3_
  - [x] 3.6 `TripDashboardVM` + `TripDashboardView`: dates, countdown/status, places map, shortcuts to Flights/Stays/Itinerary/Suggestions.
    - _Requirements: 1.7_
  - [x] 3.7 Previews for list/edit/dashboard (light + dark, large Dynamic Type) using `SampleData`. Build iOS + macOS clean.
    - _Requirements: 9.4, 9.5, 9.6_

- [x] 4. Flights
  - [x] 4.1 `FlightListView` + `FlightRow` showing per-airport local times with zone labels.
    - _Requirements: 2.2, 2.3_
  - [x] 4.2 `FlightEditVM` + `FlightEditView`: full manual entry incl. per-airport time zones, terminal/gate/ref/seat/notes.
    - _Requirements: 2.1, 2.6_
  - [x] 4.3 `FlightLookupService` protocol + `MockFlightLookupService` (deterministic data, configurable failure); "look up" action populating the form; error/offline path keeps manual entry.
    - _Requirements: 2.4, 2.5_
  - [x] 4.4 Previews + build iOS/macOS clean.
    - _Requirements: 9.6, 11.3_

- [x] 5. Stays & other bookings
  - [x] 5.1 `StayEditView` (check-in/out, place, confirmation, notes) and bookings list entry points.
    - _Requirements: 3.1_
  - [x] 5.2 `BookingEditView` (kind, time/range, place, confirmation, notes).
    - _Requirements: 3.2_
  - [x] 5.3 Edit/delete persistence for stays and bookings; previews; build clean.
    - _Requirements: 3.5, 9.6, 11.3_

- [x] 6. Daily itinerary
  - [x] 6.1 `DayItineraryVM` + `DayItineraryView`: assemble ordered `TimelineEntry` list per day from flights/stays/bookings/activities (multi-night stay check-in/out placement).
    - _Requirements: 4.1, 3.3, 3.4_
  - [x] 6.2 `ActivityEditView`: title, category, time/range, place, notes, done flag; add/edit/reorder/remove with persisted order.
    - _Requirements: 4.2, 4.3_
  - [x] 6.3 `RoutingService` protocol + `MapKitRoutingService` (async `MKDirections`, cached, typed errors); show per-leg travel time/distance; graceful degrade when unavailable.
    - _Requirements: 4.4, 4.6_
  - [x] 6.4 Pure `ScheduleEvaluator` (ok/tight/overlap vs buffer + travel, incl. before-a-flight leg) wired into the day view warnings; configurable buffer.
    - _Requirements: 4.5_
  - [x] 6.5 `DayMapView`: route of placed items in order + "Open in Apple Maps" button via route URL.
    - _Requirements: 4.7_
  - [x] 6.6 Swift Testing tests for `ScheduleEvaluator`; previews; build iOS/macOS clean.
    - _Requirements: 11.4, 4.5, 9.6, 11.3_

- [x] 7. Smart suggestions
  - [x] 7.1 Suggestion value types + `SuggestionService` protocol; `SuggestionsVM` with request form (available time presets/custom, start, area default, interests, pace) and loading/empty/error states.
    - _Requirements: 5.1, 5.6_
  - [x] 7.2 `MapKitSuggestionService`: MKLocalSearch discovery by interest categories scoped to the area region.
    - _Requirements: 5.2_
  - [x] 7.3 Pure `SuggestionPlanner`: time-fitting with injected travel estimates, per-category durations scaled by pace, opening-hours handling, arrival/departure assignment.
    - _Requirements: 5.3_
  - [x] 7.4 `SuggestionsView` + `SuggestionRow` (summary, duration, distance-from-previous, category); one-tap add-to-day creating an `Activity`.
    - _Requirements: 5.4, 5.5_
  - [x] 7.5 Empty vs error/offline states distinct and verified; Swift Testing tests for `SuggestionPlanner`; previews; build clean.
    - _Requirements: 5.6, 11.4, 9.6, 11.3_

- [x] 8. Extras
  - [x] 8.1 Notes & links attachable to a trip and to an activity; tappable links with title + URL; edit/delete.
    - _Requirements: 6.1, 6.2, 6.3_
  - [x] 8.2 `TodayVM` + `TodayView`: active trip/day with current/next highlighted in local zone; sensible state when no trip in progress.
    - _Requirements: 7.1, 7.2, 7.3_
  - [x] 8.3 `NotificationScheduling` + `LocalNotificationScheduler`: auth request + graceful denial; schedule/reschedule/cancel for flights and timed activities at a configurable lead time; keep in sync on edit/delete.
    - _Requirements: 8.1, 8.2, 8.3, 8.4_

- [x] 9. Final polish & verification
  - [x] 9.1 Audit Dark Mode + Dynamic Type across all screens via previews; fix layout issues.
    - _Requirements: 9.4, 9.5_
  - [x] 9.2 Offline pass: verify view/edit of saved data offline and that lookup/suggestions/directions show correct offline states without data loss.
    - _Requirements: 10.4, 10.5_
  - [x] 9.3 Full build for iOS and macOS with zero warnings; run the whole Swift Testing suite green.
    - _Requirements: 11.3, 11.4_
