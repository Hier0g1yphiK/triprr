//
//  DayItineraryView.swift
//  triprr
//
//  The day-by-day itinerary for a trip. A day switcher moves between the trip's
//  days (its `dayStarts`), and each day lists its flights, stays, bookings and
//  activities in time order (Req 4.1). Each row shows the item's time in its own
//  local zone with a zone label (via `DateHelpers`), an SF Symbol, title,
//  subtitle and a done indicator. An empty day shows a helpful state.
//
//  Between consecutive placed items a compact travel leg shows the estimated
//  time and distance from the injected `RoutingService`; when directions can't
//  be computed it degrades to a subtle "travel time unavailable" (Req 4.4,
//  4.6). Schedule warnings (task 6.4) attach to these rows later. Shared across
//  iPhone and Mac.
//

import SwiftUI
import SwiftData

/// Shared layout metrics for the time-in-zone timeline rows (itinerary and
/// Today), so their leading time column scales consistently with Dynamic Type.
enum TimelineRowMetrics {
    /// The time column's base width at the default content size. Fed through
    /// `@ScaledMetric` so it grows with the user's Dynamic Type setting.
    static let timeColumnBaseWidth: CGFloat = 92
}

struct DayItineraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var services

    @State private var viewModel: DayItineraryViewModel
    @State private var isAddingActivity = false
    @State private var isShowingMap = false
    @State private var editingActivity: Activity?

    init(trip: Trip) {
        _viewModel = State(initialValue: DayItineraryViewModel(trip: trip))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.dayStarts.isEmpty {
                noDaysState
            } else {
                daySwitcher
                Divider()
                dayContent
            }
        }
        .navigationTitle("Itinerary")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear { viewModel.use(routing: services.routing) }
        .task(id: travelEstimateToken) {
            await viewModel.loadTravelEstimates()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingMap = true
                } label: {
                    Label("Map", systemImage: "map")
                }
                .disabled(viewModel.placedPlacesForSelectedDay.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingActivity = true
                } label: {
                    Label("Add Activity", systemImage: "plus")
                }
                .disabled(viewModel.selectedDayStart == nil)
            }
        }
        .sheet(isPresented: $isShowingMap) {
            DayMapView(viewModel: viewModel)
        }
        .sheet(isPresented: $isAddingActivity) {
            ActivityEditView(
                mode: .create(
                    trip: viewModel.trip,
                    defaultStart: viewModel.defaultStartForNewActivity
                )
            )
        }
        .sheet(item: $editingActivity) { activity in
            ActivityEditView(mode: .edit(activity))
        }
    }

    // MARK: - Day switcher

    private var daySwitcher: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.stepDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!viewModel.canStepBackward)
            .accessibilityLabel("Previous day")

            Spacer()

            Menu {
                ForEach(viewModel.dayStarts, id: \.self) { day in
                    Button {
                        viewModel.selectedDayStart = day
                    } label: {
                        if day == viewModel.selectedDayStart {
                            Label(viewModel.dayLabel(day), systemImage: "checkmark")
                        } else {
                            Text(viewModel.dayLabel(day))
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Text(selectedDayTitle)
                        .font(.headline)
                    if let number = selectedDayNumber {
                        Text(number)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select day. Currently \(selectedDayTitle).")

            Spacer()

            Button {
                viewModel.stepDay(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.canStepForward)
            .accessibilityLabel("Next day")
        }
        .font(.title3)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var selectedDayTitle: String {
        viewModel.selectedDayStart.map(viewModel.dayLabel) ?? "—"
    }

    /// Changes whenever the selected day or its set of travel legs changes, so
    /// the estimate `task` re-runs to pick up new legs (after add / edit /
    /// reorder / delete) while reusing cached estimates for unchanged legs.
    private var travelEstimateToken: [TravelLegToken] {
        viewModel.travelLegsForSelectedDay.map {
            TravelLegToken(
                afterEntryID: $0.afterEntryID,
                destinationID: $0.destination.id,
                mode: $0.mode
            )
        }
    }

    private var selectedDayNumber: String? {
        viewModel.selectedDayStart.flatMap(viewModel.dayNumberLabel)
    }

    // MARK: - Day content

    @ViewBuilder
    private var dayContent: some View {
        if viewModel.selectedDayIsEmpty {
            emptyDayState
        } else {
            List {
                ForEach(viewModel.entriesForSelectedDay) { entry in
                    row(for: entry)
                    if let leg = legAfter(entry) {
                        TravelLegRow(leg: leg, state: viewModel.state(for: leg))
                            .deleteDisabled(true)
                            .moveDisabled(true)
                    }
                }
                .onMove(perform: moveActivities)
            }
#if os(macOS)
            .listStyle(.inset)
#endif
        }
    }

    /// The travel leg that follows `entry` on the selected day, if any.
    private func legAfter(_ entry: TimelineEntry) -> DayItineraryViewModel.TravelLeg? {
        viewModel.travelLegsForSelectedDay.first { $0.afterEntryID == entry.id }
    }

    /// A row for a timeline entry. Activity entries are tappable to edit and
    /// swipe-to-delete; flights, stays and bookings are shown but are not
    /// editable or reorderable here (Req 4.1, 4.3).
    @ViewBuilder
    private func row(for entry: TimelineEntry) -> some View {
        let warning = viewModel.scheduleWarning(for: entry)
        if let activity = viewModel.activity(for: entry) {
            Button {
                editingActivity = activity
            } label: {
                DayItineraryRow(entry: entry, warning: warning)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    delete(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            DayItineraryRow(entry: entry, warning: warning)
                .deleteDisabled(true)
                .moveDisabled(true)
        }
    }

    private var emptyDayState: some View {
        ContentUnavailableView {
            Label("Nothing planned", systemImage: "calendar.day.timeline.left")
        } description: {
            Text("Flights, stays, bookings and activities for this day will appear here in time order.")
        } actions: {
            Button {
                isAddingActivity = true
            } label: {
                Label("Add Activity", systemImage: "plus")
            }
            .disabled(viewModel.selectedDayStart == nil)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Activity mutations

    private func delete(_ entry: TimelineEntry) {
        // Cancel the pending reminder for this activity before it is removed
        // (Req 8.3). Non-activity entries resolve to nil and are skipped.
        if let id = viewModel.activity(for: entry)?.id {
            let notifications = services.notifications
            Task { await notifications.cancel(activityID: id) }
        }
        viewModel.deleteActivity(for: entry, in: modelContext)
    }

    /// Reorders activities within the selected day. `onMove` reports offsets
    /// against the full timeline; the view model maps them to the day's
    /// activities and rewrites their `sortOrder` so the order persists.
    private func moveActivities(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let entries = viewModel.entriesForSelectedDay

        // Translate the move within the full-entry list into a move within the
        // activity-only subsequence, so dragging only reorders activities and
        // ignores non-activity rows.
        let activityIndices = entries.indices.filter { viewModel.isActivity(entries[$0]) }
        guard !activityIndices.isEmpty else { return }

        // Map the dragged source positions (full-list indices) to positions
        // within the activity subsequence.
        let activityPositionByFullIndex: [Int: Int] = Dictionary(
            uniqueKeysWithValues: activityIndices.enumerated().map { ($1, $0) }
        )
        let sourceActivityPositions = offsets.compactMap { activityPositionByFullIndex[$0] }
        guard !sourceActivityPositions.isEmpty else { return }

        // Translate the full-list destination into an activity-subsequence
        // destination: count how many activities sit before it.
        let activityDestination = activityIndices.filter { $0 < destination }.count

        viewModel.moveActivities(
            fromOffsets: IndexSet(sourceActivityPositions),
            toOffset: activityDestination,
            in: modelContext
        )
    }

    private var noDaysState: some View {
        ContentUnavailableView {
            Label("No trip days", systemImage: "calendar")
        } description: {
            Text("Set the trip's start and end dates to lay out its days.")
        }
    }
}

/// A lightweight, `Equatable` identity for a day's travel legs, used as the
/// `.task(id:)` token so estimates re-load only when the legs actually change.
private struct TravelLegToken: Equatable {
    let afterEntryID: UUID
    let destinationID: UUID
    let mode: TravelMode
}

// MARK: - Row

/// A single timeline entry: its time in the entry's own zone (with a zone
/// label), SF Symbol, title, optional subtitle and a done indicator. A travel
/// leg (``TravelLegRow``) renders beneath the row when the next placed item has
/// a route. When reaching this item from the previous one is too tight, a
/// subtle schedule warning badge appears on the row — amber for a tight
/// connection, red for an overlap (Req 4.5).
struct DayItineraryRow: View {
    let entry: TimelineEntry
    /// The schedule gap the row should warn about (the gap *preceding* this
    /// item), or `nil` when reaching it is comfortable.
    var warning: ScheduleGap?

    /// The time column's width, scaled with Dynamic Type so a time range plus
    /// zone label stays legible at accessibility sizes instead of truncating.
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth = TimelineRowMetrics.timeColumnBaseWidth

    init(entry: TimelineEntry, warning: ScheduleGap? = nil) {
        self.entry = entry
        self.warning = warning
    }

    private var timeLabel: String {
        if let end = entry.end {
            let start = DateHelpers.timeString(entry.start, in: entry.timeZone)
            let endTime = DateHelpers.timeString(end, in: entry.timeZone)
            return "\(start) – \(endTime)"
        }
        return DateHelpers.timeString(entry.start, in: entry.timeZone)
    }

    private var zoneLabel: String {
        DateHelpers.zoneAbbreviation(entry.start, in: entry.timeZone)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                Text(zoneLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: timeColumnWidth, alignment: .trailing)

            Image(systemName: entry.symbolName)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .strikethrough(entry.isDone, color: .secondary)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let warning, let text = warning.warningText {
                    scheduleWarningBadge(text, verdict: warning.verdict)
                }
            }

            Spacer(minLength: 0)

            if entry.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// A compact, colour-coded warning badge: amber for a tight connection,
    /// red for an overlap. Kept unobtrusive (caption, icon + short label) and
    /// surfaced to VoiceOver via the row's combined accessibility label.
    @ViewBuilder
    private func scheduleWarningBadge(_ text: String, verdict: ScheduleVerdict) -> some View {
        Label(text, systemImage: verdict == .overlap ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
            .font(.caption2.weight(.medium))
            .foregroundStyle(verdict == .overlap ? Color.red : Color.orange)
            .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        var parts = ["\(entry.title), \(DateHelpers.timeStringWithZone(entry.start, in: entry.timeZone))"]
        if let subtitle = entry.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if entry.isDone { parts.append("done") }
        if let warning, let text = warning.warningText { parts.append(text) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Travel leg

/// A compact "travel leg" shown between two consecutive placed items: either an
/// estimate ("15 min · 3.2 km · Driving") once resolved, a subtle loading
/// placeholder while computing, or a subtle "Travel time unavailable" when
/// directions can't be computed (offline, no route) — degrading gracefully
/// rather than failing the day view (Req 4.4, 4.6).
struct TravelLegRow: View {
    let leg: DayItineraryViewModel.TravelLeg
    let state: DayItineraryViewModel.LegState?

    /// Matches ``DayItineraryRow``'s scaled time column so the connector stays
    /// aligned under the gutter at every Dynamic Type size.
    @ScaledMetric(relativeTo: .subheadline) private var timeColumnWidth = TimelineRowMetrics.timeColumnBaseWidth

    var body: some View {
        HStack(spacing: 12) {
            // Align the connector under the row's time column / symbol gutter.
            Color.clear.frame(width: timeColumnWidth)

            Image(systemName: connectorSymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            label
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var connectorSymbol: String {
        switch state {
        case .estimate(let estimate): estimate.mode.symbolName
        default: leg.mode.symbolName
        }
    }

    @ViewBuilder
    private var label: some View {
        switch state {
        case .estimate(let estimate):
            Text(estimate.compactLabel)
        case .loading, .none:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Estimating travel…")
            }
        case .unavailable:
            Text("Travel time unavailable")
                .italic()
        }
    }

    private var accessibilityDescription: String {
        switch state {
        case .estimate(let estimate):
            "Travel to next: \(estimate.timeLabel), \(estimate.distanceLabel), \(estimate.mode.displayName)"
        case .loading, .none:
            "Estimating travel to next item"
        case .unavailable:
            "Travel time to next item unavailable"
        }
    }
}

// MARK: - Previews

#Preview("Itinerary — Light") {
    NavigationStack {
        DayItineraryView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Itinerary — Dark") {
    NavigationStack {
        DayItineraryView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Itinerary — Large Type") {
    NavigationStack {
        DayItineraryView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Itinerary — Empty Day") {
    NavigationStack {
        DayItineraryView(trip: SampleData.makeUpcomingParisTrip())
    }
    .modelContainer(SampleData.emptyContainer())
    .environment(\.appServices, .mock)
}

#Preview("Itinerary — Routing Unavailable") {
    NavigationStack {
        DayItineraryView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(
        \.appServices,
        AppServices(routing: MockRoutingService(errorToThrow: .offline))
    )
}

// MARK: - Row & leg previews (fixtures)

/// A fixed instant so the row previews render deterministic times.
private let rowPreviewBase = Date(timeIntervalSince1970: 1_700_000_000)

/// A sample timeline entry for the row previews, backed by `SampleData`.
private func previewEntry(
    title: String,
    minutesFromBase: Double = 0,
    durationMinutes: Double? = 90,
    place: Place? = SampleData.teamLab,
    symbol: String = "building.columns",
    isDone: Bool = false
) -> TimelineEntry {
    let start = rowPreviewBase.addingTimeInterval(minutesFromBase * 60)
    return TimelineEntry(
        id: UUID(),
        source: .activity(activityID: UUID()),
        title: title,
        subtitle: place?.name,
        start: start,
        end: durationMinutes.map { start.addingTimeInterval($0 * 60) },
        timeZoneIdentifier: "Asia/Tokyo",
        place: place,
        symbolName: symbol,
        sortOrder: 0,
        isDone: isDone
    )
}

/// A schedule gap of a given verdict, for the warning-badge preview.
private func previewGap(_ verdict: ScheduleVerdict, nextIsFlight: Bool = false) -> ScheduleGap {
    ScheduleGap(
        afterEntryID: UUID(),
        beforeEntryID: UUID(),
        verdict: verdict,
        slackSeconds: verdict == .overlap ? -600 : (verdict == .tight ? 300 : 3600),
        nextIsFlight: nextIsFlight
    )
}

private func previewLeg() -> DayItineraryViewModel.TravelLeg {
    DayItineraryViewModel.TravelLeg(
        afterEntryID: UUID(),
        origin: SampleData.teamLab,
        destination: SampleData.sensoji,
        mode: .automobile
    )
}

#Preview("DayItineraryRow — Warnings (Light)") {
    List {
        DayItineraryRow(entry: previewEntry(title: "teamLab Planets"))
        DayItineraryRow(
            entry: previewEntry(title: "Sensō-ji Temple", minutesFromBase: 120, symbol: "building.columns"),
            warning: previewGap(.tight)
        )
        DayItineraryRow(
            entry: previewEntry(title: "Robot Restaurant Show", minutesFromBase: 240, symbol: "ticket"),
            warning: previewGap(.overlap)
        )
        DayItineraryRow(
            entry: previewEntry(title: "Flight BA005", minutesFromBase: 360, durationMinutes: nil, place: SampleData.haneda, symbol: "airplane"),
            warning: previewGap(.tight, nextIsFlight: true)
        )
    }
    .preferredColorScheme(.light)
}

#Preview("DayItineraryRow — Warnings (Dark)") {
    List {
        DayItineraryRow(
            entry: previewEntry(title: "Sensō-ji Temple", symbol: "building.columns"),
            warning: previewGap(.tight)
        )
        DayItineraryRow(
            entry: previewEntry(title: "Robot Restaurant Show", minutesFromBase: 120, symbol: "ticket"),
            warning: previewGap(.overlap)
        )
        DayItineraryRow(
            entry: previewEntry(title: "Flight BA005", minutesFromBase: 240, durationMinutes: nil, place: SampleData.haneda, symbol: "airplane"),
            warning: previewGap(.overlap, nextIsFlight: true)
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("DayItineraryRow — Warnings (Large Type)") {
    List {
        DayItineraryRow(
            entry: previewEntry(title: "Sensō-ji Temple", symbol: "building.columns"),
            warning: previewGap(.tight)
        )
        DayItineraryRow(
            entry: previewEntry(title: "Flight BA005", minutesFromBase: 120, durationMinutes: nil, place: SampleData.haneda, symbol: "airplane"),
            warning: previewGap(.overlap, nextIsFlight: true)
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("TravelLegRow — States (Light)") {
    List {
        TravelLegRow(
            leg: previewLeg(),
            state: .estimate(RouteEstimate(travelTime: 15 * 60, distance: 3_200, mode: .automobile))
        )
        TravelLegRow(leg: previewLeg(), state: .loading)
        TravelLegRow(leg: previewLeg(), state: .unavailable)
    }
    .preferredColorScheme(.light)
}

#Preview("TravelLegRow — States (Dark)") {
    List {
        TravelLegRow(
            leg: previewLeg(),
            state: .estimate(RouteEstimate(travelTime: 42 * 60, distance: 12_600, mode: .transit))
        )
        TravelLegRow(leg: previewLeg(), state: .loading)
        TravelLegRow(leg: previewLeg(), state: .unavailable)
    }
    .preferredColorScheme(.dark)
}
