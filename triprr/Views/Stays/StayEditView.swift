//
//  StayEditView.swift
//  triprr
//
//  Create or edit a stay (hotel or rental): name, kind, place (via
//  PlaceSearchField), check-in and check-out instants with a time zone, a
//  confirmation number and notes (Req 3.1). Instants are stored in UTC and
//  interpreted in the chosen zone, which defaults from the place or the trip's
//  primary zone. Check-out may not precede check-in. Saving persists via the
//  ModelContext and reflects immediately (Req 3.5).
//

import SwiftUI
import SwiftData

struct StayEditView: View {
    enum Mode {
        case create(Trip)
        case edit(Stay)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String = ""
    @State private var kind: StayKind = .hotel
    @State private var place: Place?
    /// Wall-clock values the user picks; combined with `zoneIdentifier` to
    /// produce the stored UTC instants.
    @State private var checkInLocal: Date = Date()
    @State private var checkOutLocal: Date = Date()
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

    private var checkInInstant: Date {
        TimeZoneConversion.instant(from: checkInLocal, in: timeZone)
    }

    private var checkOutInstant: Date {
        TimeZoneConversion.instant(from: checkOutLocal, in: timeZone)
    }

    private var nameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Check-out must not precede check-in.
    private var datesValid: Bool { checkOutInstant >= checkInInstant }
    private var canSave: Bool { nameValid && datesValid }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                placeSection
                datesSection
                confirmationSection
                notesSection
            }
            .navigationTitle(isEditing ? "Edit Stay" : "New Stay")
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
        Section("Stay") {
            TextField("Name", text: $name)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            if !nameValid {
                Label("Enter a name for the stay.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Kind", selection: $kind) {
                ForEach(StayKind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }
        }
    }

    private var placeSection: some View {
        Section("Place") {
            PlaceSearchField(selection: $place, prompt: "Search for the hotel or rental")
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            DatePicker(
                "Check-in",
                selection: $checkInLocal,
                displayedComponents: [.date, .hourAndMinute]
            )
            .onChange(of: checkInLocal) { _, newValue in
                if checkOutLocal < newValue { checkOutLocal = newValue }
            }

            DatePicker(
                "Check-out",
                selection: $checkOutLocal,
                displayedComponents: [.date, .hourAndMinute]
            )

            ZoneIdentifierPicker(title: "Time Zone", selection: $zoneIdentifier)

            Label(
                "Check-in \(DateHelpers.timeStringWithZone(checkInInstant, in: timeZone))",
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !datesValid {
                Label(
                    "Check-out can't be before check-in.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    private var confirmationSection: some View {
        Section("Confirmation") {
            TextField("Confirmation Number", text: $confirmationNumber)
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
            // A sensible default: check in this afternoon, check out next day.
            checkInLocal = TimeZoneConversion.localTime(from: now, in: zone)
            checkOutLocal = checkInLocal.addingTimeInterval(24 * 3600)

        case .edit(let stay):
            name = stay.name
            kind = stay.kind
            place = stay.place
            zoneIdentifier = stay.effectiveTimeZone.identifier
            checkInLocal = TimeZoneConversion.localTime(from: stay.checkIn, in: stay.effectiveTimeZone)
            checkOutLocal = TimeZoneConversion.localTime(from: stay.checkOut, in: stay.effectiveTimeZone)
            confirmationNumber = stay.confirmationNumber ?? ""
            notes = stay.notes ?? ""
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create(let trip):
            let stay = Stay(
                name: trimmedName,
                kind: kind,
                place: place,
                checkIn: checkInInstant,
                checkOut: checkOutInstant,
                timeZoneIdentifier: zoneIdentifier,
                confirmationNumber: optional(confirmationNumber),
                notes: optional(notes),
                trip: trip
            )
            modelContext.insert(stay)

        case .edit(let stay):
            stay.name = trimmedName
            stay.kind = kind
            stay.place = place
            stay.checkIn = checkInInstant
            stay.checkOut = checkOutInstant
            stay.timeZoneIdentifier = zoneIdentifier
            stay.confirmationNumber = optional(confirmationNumber)
            stay.notes = optional(notes)
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
    StayEditView(mode: .create(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}

#Preview("Edit — Light") {
    StayEditView(mode: .edit(SampleData.makeTokyoTrip().stays[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    StayEditView(mode: .edit(SampleData.makeTokyoTrip().stays[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Large Type") {
    StayEditView(mode: .edit(SampleData.makeTokyoTrip().stays[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}
