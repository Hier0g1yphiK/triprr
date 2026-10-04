# Requirements — Triprr

## Introduction

Triprr is a native travel itinerary app for iPhone and Mac, built with Swift 6 and SwiftUI from
a single multiplatform target. It gathers everything about a trip in one place — flights, stays,
day-by-day plans, and ideas for what to do — and works fully offline once data is saved. Its
standout capability is suggesting things to do in a city that realistically fit the amount of time
the user has there, using Apple's MapKit so that no paid third-party API or key is required for the
core app.

The app persists with SwiftData, stores instants in UTC and displays them in the local time zone of
the place involved, and keeps anything that would need an external service (flight lookup, weather,
curated suggestions) behind a protocol with a mock or local implementation shipping first.

### Scope of this release (MVP)

In scope: trips, flights, stays and other bookings, a daily itinerary with travel-time and buffer
warnings, smart time-aware suggestions, notes/links, a "Today" screen, and local notifications.

Out of scope (data models must leave room for these later): accounts, cloud sync, collaboration or
sharing, email forwarding/parsing, expense tracking, document storage, Apple Watch, widgets.

### Platform & tooling baseline (from the existing project)

- Single app target `triprr` with `triprrTests` (Swift Testing) and `triprrUITests`.
- Deployment target 26.5 for iOS, macOS and xrOS; built with Xcode 26.6.
- `SWIFT_VERSION` is currently 5.0 and must be raised to 6.0 to meet the Swift 6 constraint;
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` are already set.
- macOS target has `ENABLE_APP_SANDBOX = YES`; a network entitlement is required for MapKit requests.
- SwiftData and Swift Testing are already wired into the template.

### Terminology

- **Instant**: a precise moment in time, stored as a UTC `Date`.
- **Place**: a saved location (name, coordinate, optional address) derived from a MapKit `MKMapItem`.
- **Booking**: a reserved item with a confirmation — a stay, flight, or "other booking".
- **Activity**: an itinerary entry on a specific day (visit, meal, free-form plan, or an added suggestion).
- **Buffer**: the minimum slack time the user wants between consecutive items (configurable).

---

## Requirement 1 — Trips

**User story:** As a traveller, I want to create and manage trips with their key details, so that I
have one record per journey to organise everything around.

### Acceptance criteria

1. WHEN the user creates a trip THEN the system SHALL require a name and a start date and an end date,
   and SHALL allow one or more destinations and an optional cover (a chosen colour, or an image).
2. IF the end date is before the start date WHEN the user tries to save THEN the system SHALL block the
   save and show a validation message.
3. WHEN the user edits or deletes a trip THEN the system SHALL persist the change with SwiftData and
   reflect it immediately in every open view.
4. WHEN a trip is deleted THEN the system SHALL also delete its flights, stays, bookings, activities,
   notes and links (cascade), and SHALL confirm before deleting a trip that contains items.
5. WHEN the trip list is shown THEN the system SHALL group trips into Upcoming, Current and Past based
   on the current date relative to the trip's start and end dates, and SHALL sort sensibly within each group.
6. WHEN a trip has no items yet THEN the system SHALL show a helpful empty state.
7. WHEN a trip dashboard is shown THEN the system SHALL display the dates, a live countdown (or "in
   progress"/"ended"), a map of the trip's places, and shortcuts to Flights, Stays, Itinerary and Suggestions.
8. WHEN destinations are entered THEN the system SHALL let the user attach a place via MapKit search so
   the dashboard map and the trip's default time zone can be derived from it.

---

## Requirement 2 — Flights

**User story:** As a traveller, I want to record my flights with accurate local times, so that I always
know when and where to be, in the right time zone.

### Acceptance criteria

1. WHEN the user adds a flight THEN the system SHALL accept airline, flight number, departure and arrival
   airports, scheduled departure and arrival instants each with their own time zone, and optional terminal,
   gate, booking reference, seat and notes.
2. WHEN a flight time is displayed THEN the system SHALL show it in the local time zone of the relevant
   airport and SHALL label the zone, deriving each airport's zone from its place.
3. WHEN flights exist for a trip THEN the system SHALL place each flight in the trip timeline and in the
   correct day(s) of the day view using the departure instant in the departure airport's local day.
4. WHEN the user requests a flight lookup THEN the system SHALL call a `FlightLookupService` taking a flight
   number and a date and returning flight details, SHALL ship a mock implementation now, and SHALL keep a
   clear seam for adding a real provider later without changing the UI.
5. IF a flight lookup fails or is offline THEN the system SHALL surface a clear error and still allow manual entry.
6. WHEN the user edits or deletes a flight THEN the system SHALL persist and reflect the change immediately.

---

## Requirement 3 — Stays and other bookings

**User story:** As a traveller, I want to record where I'm staying and other reserved items, so that all
my confirmations live beside the trip they belong to.

### Acceptance criteria

1. WHEN the user adds a stay (hotel or rental) THEN the system SHALL accept check-in and check-out instants,
   address/place, confirmation number and notes.
2. WHEN the user adds an other booking (restaurant reservation, tour, ticket, transport) THEN the system SHALL
   accept a type/category, a time (or time range), a place, confirmation details and notes.
3. WHEN a stay or booking has a time that falls on a trip day THEN the system SHALL show it in that day's itinerary.
4. WHEN a stay spans multiple nights THEN the system SHALL represent check-in on the arrival day and check-out
   on the departure day in the itinerary.
5. WHEN the user edits or deletes a stay or booking THEN the system SHALL persist and reflect the change immediately.

---

## Requirement 4 — Daily itinerary

**User story:** As a traveller, I want a day-by-day plan with travel times and warnings, so that each
day is realistic and I know how to get between places.

### Acceptance criteria

1. WHEN a trip day is shown THEN the system SHALL list every item for that day (activities, flights, stays,
   bookings) in time order.
2. WHEN the user adds or edits an activity THEN the system SHALL accept a title, a category, a time or time
   range, an optional place searchable via MapKit, notes and a done flag.
3. WHEN the user reorders or removes activities THEN the system SHALL persist the new order/removal and reflect it immediately.
4. WHEN two consecutive items both have places THEN the system SHALL show an estimated travel time and distance
   between them using MapKit directions, and SHALL choose a travel mode (default automobile, configurable per leg or trip).
5. IF the gap between the end of one item and the start of the next (or before a flight) is less than the
   configurable buffer plus the estimated travel time THEN the system SHALL show a warning on the affected item.
6. WHEN directions cannot be computed (offline, no route, or missing place) THEN the system SHALL degrade gracefully:
   show the items without a travel estimate and indicate the estimate is unavailable rather than failing the day view.
7. WHEN a day is shown THEN the system SHALL offer a map view plotting the day's placed items as a route in time
   order, with a button to open the route in Apple Maps.

---

## Requirement 5 — Smart suggestions (key feature)

**User story:** As a traveller with limited time in a city, I want suggestions for what to do that fit
the time I have, so that I make the most of the day without over-planning.

### Acceptance criteria

1. WHEN the user requests suggestions THEN the system SHALL accept: available time (presets such as 4 hours /
   half day / full day, plus a custom duration), a start time, a city/area (defaulting to the trip or day's
   place), optional interests (food, museums, outdoors, nightlife, shopping, landmarks), and a pace (relaxed or packed).
2. WHEN suggestions are generated THEN the system SHALL use a `SuggestionService` protocol with a MapKit-based
   implementation (MKLocalSearch for the city and chosen categories), keeping the logic swappable/extendable.
3. WHEN fitting suggestions to the time THEN the system SHALL account for realistic travel time between places
   (MapKit), an estimated visit duration per category, pace, and opening hours where MapKit provides them, and
   SHALL return a set that fits within the available time starting at the start time.
4. WHEN a suggestion is shown THEN the system SHALL display a short summary, estimated visit duration, distance
   from the previous stop, and category.
5. WHEN the user taps add on a suggestion THEN the system SHALL create a corresponding activity on the chosen
   day's itinerary in one tap, at a sensible time.
6. WHEN there are no results THEN the system SHALL show a clear empty state; WHEN generation fails or the device
   is offline THEN the system SHALL show a clear error state distinct from the empty state.

---

## Requirement 6 — Notes and links

**User story:** As a traveller, I want to attach notes and links to a trip or an activity, so that
reference material stays with the thing it relates to.

### Acceptance criteria

1. WHEN the user adds a note or a link to a trip or an activity THEN the system SHALL persist it and show it
   in that item's detail.
2. WHEN a link is shown THEN the system SHALL make it tappable to open, and SHALL store a title alongside the URL.
3. WHEN the user edits or deletes a note or link THEN the system SHALL persist and reflect the change immediately.

---

## Requirement 7 — Today screen

**User story:** As a traveller mid-trip, I want a "Today" screen, so that I can see what's happening
now and next at a glance.

### Acceptance criteria

1. WHEN a trip is in progress (current date within its range) THEN the system SHALL offer a Today screen for
   that trip showing the current day's items in time order with the current/next item highlighted.
2. WHEN no trip is currently in progress THEN the system SHALL show a sensible state (e.g. the next upcoming
   trip with a countdown, or an empty state).
3. WHEN the Today screen is shown THEN the system SHALL use the local time zone of the current day's place for "now".

---

## Requirement 8 — Local notifications

**User story:** As a traveller, I want reminders before flights and activities, so that I don't miss anything.

### Acceptance criteria

1. WHEN the app first needs to notify THEN the system SHALL request local notification authorization and SHALL
   handle denial gracefully (feature off, no crash).
2. WHEN a flight or a timed activity exists in the future THEN the system SHALL schedule a local notification at
   a configurable lead time before it, in the correct local time zone.
3. WHEN the underlying item's time changes or it is deleted THEN the system SHALL reschedule or cancel the
   corresponding notification.
4. WHEN notifications are unavailable or denied THEN the rest of the app SHALL continue to function fully.

---

## Requirement 9 — Platform experience (iPhone and Mac)

**User story:** As someone who uses both iPhone and Mac, I want the app to feel native on each, so that it
fits the platform while sharing the same data and logic.

### Acceptance criteria

1. WHEN the app runs on Mac THEN the system SHALL present a sidebar of trips with a detail area for the selected trip.
2. WHEN the app runs on iPhone THEN the system SHALL present the same trip hierarchy via a tab bar and/or navigation stack.
3. WHEN platform layouts differ THEN the system SHALL share models, services and view models across platforms and
   SHALL use platform-specific views only where the layout genuinely differs.
4. WHEN the user switches between light and dark appearance THEN the system SHALL look correct in both.
5. WHEN the user changes Dynamic Type size THEN the system SHALL scale text and remain usable.
6. WHEN views are previewed in Xcode THEN the system SHALL provide previews backed by in-memory sample data.

---

## Requirement 10 — Persistence, time zones, and offline

**User story:** As a traveller, I want my data saved correctly and usable without a connection, so that
I can rely on it anywhere, including on a plane.

### Acceptance criteria

1. WHEN any entity is created or changed THEN the system SHALL persist it with SwiftData in a container shared by
   the app (and configured for in-memory use in previews/tests).
2. WHEN an instant is stored THEN the system SHALL store it in UTC and SHALL store the associated time zone
   identifier separately where a place's local time matters (flights, bookings, activities).
3. WHEN an instant is displayed THEN the system SHALL render it in the relevant place's local time zone with a clear zone label.
4. WHEN the device is offline AND data has been saved THEN the system SHALL allow full viewing and editing of trips,
   flights, stays, bookings, itineraries, notes and links.
5. WHEN an online-only feature is used offline (flight lookup, suggestions, directions) THEN the system SHALL show a
   clear offline state and SHALL NOT lose or corrupt saved data.

---

## Requirement 11 — Architecture, quality and build

**User story:** As the developer, I want the code layered and the build clean, so that the app is
maintainable and each step is shippable.

### Acceptance criteria

1. WHEN code is organised THEN the system SHALL separate Models, Services (protocols + implementations), ViewModels
   and Views into clear layers.
2. WHEN an external capability is needed (flight lookup, suggestions, directions/travel time) THEN the system SHALL
   define it as a protocol and provide a mock or MapKit-local implementation first, so a real provider can be added
   without changing the UI.
3. WHEN the project is built for iOS and for macOS THEN the system SHALL build cleanly with no warnings under Swift 6.
4. WHEN date/time-zone logic, schedule-buffer warnings, and suggestion time-fitting are implemented THEN the system
   SHALL have Swift Testing unit tests covering them.
5. WHEN the work is sequenced THEN each step SHALL leave the app building and runnable: persistence/models first,
   then trips, then bookings and flights, then the itinerary, then suggestions, then extras.
