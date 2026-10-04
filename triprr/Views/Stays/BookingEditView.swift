//
//  BookingEditView.swift
//  triprr
//
//  Create or edit an "other booking" (restaurant reservation, tour, ticket,
//  transport or other): title, kind, a start time plus an optional end time
//  (a time range), place (via PlaceSearchField), confirmation details and
//  notes (Req 3.2). Instants are stored in UTC and interpreted in the chosen
//  zone, which defaults from the place or the trip's primary zone. When an end
//  time is enabled it may not precede the start. Saving persists via the
//  ModelContext and reflects immediately (Req 3.5).
//

import SwiftUI
import SwiftData

struct BookingEditView: View {
    enum Mode {
        case create(Trip)
        case edit(Booking)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title: String = ""
    @State private var kind: BookingKind = .other
    @State private var place: Place?
    /// Wall-clock values the user picks; combined with `zoneIdentifier` to
    /// produce the stored UTC instants.
    @State private var startLocal: Date = Date()
    @State private var endLocal: Date = Date()
    /// Whether this booking is a time range rather than a single instant.
    @State private var hasEnd: Bool = false
    @State private var zoneIdentifier: String = TimeZone.current.identifier
    @State private var confirmationNumber: String = ""
    @State private var notes: String = ""
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
                confirmationSection
                notesSection
            }
            .navigationTitle(isEditing ? "Edit Booking" : "New Booking")
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
        Section("Booking") {
            TextField("Title", text: $title)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            if !titleValid {
                Label("Enter a title for the booking.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Kind", selection: $kind) {
                ForEach(BookingKind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
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

    private var confirmationSection: some View {
        Section("Confirmation") {
            TextField("Confirmation Details", text: $confirmationNumber)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Load / Save

    private func load() {
        guard !didLoad else { return }
        didLoad = true

        switch mode {
        case .create(let trip):
            // Default the zone from the trip's primary place.
            zoneIdentifier = trip.primaryTimeZone.identifier
            let now = Date()
            let zone = TimeZone(identifier: zoneIdentifier) ?? .current
            startLocal = TimeZoneConversion.localTime(from: now, in: zone)
            endLocal = startLocal.addingTimeInterval(2 * 3600)

        case .edit(let booking):
            title = booking.title
            kind = booking.kind
            place = booking.place
            zoneIdentifier = booking.effectiveTimeZone.identifier
            startLocal = TimeZoneConversion.localTime(from: booking.startDate, in: booking.effectiveTimeZone)
            if let end = booking.endDate {
                hasEnd = true
                endLocal = TimeZoneConversion.localTime(from: end, in: booking.effectiveTimeZone)
            } else {
                hasEnd = false
                endLocal = startLocal.addingTimeInterval(2 * 3600)
            }
            confirmationNumber = booking.confirmationNumber ?? ""
            notes = booking.notes ?? ""
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create(let trip):
            let booking = Booking(
                title: trimmedTitle,
                kind: kind,
                place: place,
                startDate: startInstant,
                endDate: endInstant,
                timeZoneIdentifier: zoneIdentifier,
                confirmationNumber: optional(confirmationNumber),
                notes: optional(notes),
                trip: trip
            )
            modelContext.insert(booking)

        case .edit(let booking):
            booking.title = trimmedTitle
            booking.kind = kind
            booking.place = place
            booking.startDate = startInstant
            booking.endDate = endInstant
            booking.timeZoneIdentifier = zoneIdentifier
            booking.confirmationNumber = optional(confirmationNumber)
            booking.notes = optional(notes)
        }

        try? modelContext.save()
        dismiss()
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Create") {
    BookingEditView(mode: .create(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}

#Preview("Edit — Light") {
    BookingEditView(mode: .edit(SampleData.makeTokyoTrip().bookings[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    BookingEditView(mode: .edit(SampleData.makeTokyoTrip().bookings[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Large Type") {
    BookingEditView(mode: .edit(SampleData.makeTokyoTrip().bookings[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}
