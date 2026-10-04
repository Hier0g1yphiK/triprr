//
//  ActivityEditView.swift
//  triprr
//
//  Create or edit an itinerary Activity: title, category (an ActivityCategory
//  picker with SF Symbols and display names), a start instant plus an optional
//  end (a time range via a "has end time" toggle), place (via PlaceSearchField),
//  notes and an isDone flag (Req 4.2). Instants are stored in UTC and
//  interpreted in the chosen zone, which defaults from the place or the trip's
//  primary zone. When an end time is enabled it may not precede the start.
//  Saving persists via the ModelContext and reflects immediately (Req 4.3).
//
//  On create, the new activity is appended after the day's existing activities
//  by giving it the next sortOrder, so it reads as "added to the end" of the
//  day until the user reorders (Req 4.3).
//

import SwiftUI
import SwiftData

struct ActivityEditView: View {
    enum Mode {
        /// Create a new activity for `trip`. `defaultStart`, when provided, seeds
        /// the start instant (e.g. the selected day in the itinerary).
        case create(trip: Trip, defaultStart: Date?)
        case edit(Activity)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    let mode: Mode

    @State private var title: String = ""
    @State private var category: ActivityCategory = .other
    @State private var place: Place?
    /// Wall-clock values the user picks; combined with `zoneIdentifier` to
    /// produce the stored UTC instants.
    @State private var startLocal: Date = Date()
    @State private var endLocal: Date = Date()
    /// Whether this activity is a time range rather than a single instant.
    @State private var hasEnd: Bool = false
    @State private var zoneIdentifier: String = TimeZone.current.identifier
    @State private var notes: String = ""
    @State private var isDone: Bool = false
    @State private var didLoad = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var timeZone: TimeZone {
        TimeZone(identifier: zoneIdentifier) ?? .current
    }

    private var startInstant: Date {
        TimeZoneConversion.instant(from: startLocal, in: timeZone)
    }

    private var endInstant: Date? {
        hasEnd ? TimeZoneConversion.instant(from: endLocal, in: timeZone) : nil
    }

    private var titleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// When an end time is enabled it must not precede the start.
    private var rangeValid: Bool {
        guard let endInstant else { return true }
        return endInstant >= startInstant
    }

    private var canSave: Bool { titleValid && rangeValid }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                placeSection
                timeSection
                notesSection
                statusSection
                if case .edit(let activity) = mode {
                    NotesLinksSection(owner: .activity(activity))
                }
            }
            .navigationTitle(isEditing ? "Edit Activity" : "New Activity")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: place) { _, newPlace in
                // Adopt the place's zone when it carries one.
                if let identifier = newPlace?.timeZoneIdentifier {
                    zoneIdentifier = identifier
                }
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Activity") {
            TextField("Title", text: $title)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            if !titleValid {
                Label("Enter a title for the activity.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Category", selection: $category) {
                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    Label(category.displayName, systemImage: category.symbolName).tag(category)
                }
            }
        }
    }

    private var placeSection: some View {
        Section("Place") {
            PlaceSearchField(selection: $place, prompt: "Search for the place")
        }
    }

    private var timeSection: some View {
        Section("Time") {
            DatePicker(
                "Starts",
                selection: $startLocal,
                displayedComponents: [.date, .hourAndMinute]
            )
            .onChange(of: startLocal) { _, newValue in
                if endLocal < newValue { endLocal = newValue }
            }

            Toggle("Has end time", isOn: $hasEnd.animation())

            if hasEnd {
                DatePicker(
                    "Ends",
                    selection: $endLocal,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            ZoneIdentifierPicker(title: "Time Zone", selection: $zoneIdentifier)

            Label(
                "Starts \(DateHelpers.timeStringWithZone(startInstant, in: timeZone))",
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !rangeValid {
                Label(
                    "End time can't be before the start.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    private var notesSection: some View {
        Section("Quick Note") {
            TextField("A short note", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            Toggle("Done", isOn: $isDone)
        }
    }

    // MARK: - Load / Save

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .create(let trip, let defaultStart):
            // Default the zone from the trip's primary place.
            zoneIdentifier = trip.primaryTimeZone.identifier
            let zone = TimeZone(identifier: zoneIdentifier) ?? .current
            let base = defaultStart ?? Date()
            startLocal = TimeZoneConversion.localTime(from: base, in: zone)
            endLocal = startLocal.addingTimeInterval(2 * 3600)

        case .edit(let activity):
            title = activity.title
            category = activity.category
            place = activity.place
            zoneIdentifier = activity.effectiveTimeZone.identifier
            startLocal = TimeZoneConversion.localTime(from: activity.startDate, in: activity.effectiveTimeZone)
            if let end = activity.endDate {
                hasEnd = true
                endLocal = TimeZoneConversion.localTime(from: end, in: activity.effectiveTimeZone)
            } else {
                hasEnd = false
                endLocal = startLocal.addingTimeInterval(2 * 3600)
            }
            notes = activity.notes ?? ""
            isDone = activity.isDone
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let saved: Activity
        switch mode {
        case .create(let trip, _):
            let activity = Activity(
                title: trimmedTitle,
                category: category,
                startDate: startInstant,
                endDate: endInstant,
                timeZoneIdentifier: zoneIdentifier,
                place: place,
                notes: optional(notes),
                isDone: isDone,
                sortOrder: nextSortOrder(for: trip),
                trip: trip
            )
            modelContext.insert(activity)
            saved = activity

        case .edit(let activity):
            activity.title = trimmedTitle
            activity.category = category
            activity.place = place
            activity.startDate = startInstant
            activity.endDate = endInstant
            activity.timeZoneIdentifier = zoneIdentifier
            activity.notes = optional(notes)
            activity.isDone = isDone
            saved = activity
        }

        try? modelContext.save()

        // Keep this activity's reminder in sync: schedule/reschedule a timed
        // reminder a lead time before its start (a safe no-op if denied),
        // replacing any prior request by its stable identifier (Req 8.2, 8.3).
        let notifications = services.notifications
        Task { await notifications.sync(activity: saved) }

        dismiss()
    }

    /// The next sortOrder to append a new activity after the trip's existing
    /// ones, so a freshly created activity reads at the end of its slot until
    /// reordered (Req 4.3).
    private func nextSortOrder(for trip: Trip) -> Int {
        (trip.activities.map(\.sortOrder).max() ?? -1) + 1
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Create") {
    ActivityEditView(mode: .create(trip: SampleData.makeTokyoTrip(), defaultStart: nil))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}

#Preview("Edit — Light") {
    ActivityEditView(mode: .edit(SampleData.makeTokyoTrip().activities[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    ActivityEditView(mode: .edit(SampleData.makeTokyoTrip().activities[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Large Type") {
    ActivityEditView(mode: .edit(SampleData.makeTokyoTrip().activities[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}
