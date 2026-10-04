//
//  FlightEditView.swift
//  triprr
//
//  Create or edit a flight with full manual entry: airline, flight number,
//  departure/arrival airports (via PlaceSearchField), scheduled departure and
//  arrival instants each with their own time zone, plus optional terminal,
//  gate, booking reference, seat and notes (Req 2.1). Instants are stored in
//  UTC; each airport's zone defaults from its place and can be picked/confirmed
//  by the user. Saving persists via the ModelContext and reflects immediately
//  (Req 2.6).
//

import SwiftUI
import SwiftData

struct FlightEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    @State private var viewModel: FlightEditViewModel

    init(mode: FlightEditViewModel.Mode) {
        _viewModel = State(initialValue: FlightEditViewModel(mode: mode))
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                lookupSection
                departureSection
                arrivalSection
                optionalDetailsSection
                notesSection
            }
            .navigationTitle(viewModel.isEditing ? "Edit Flight" : "New Flight")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .onAppear { viewModel.use(flightLookup: services.flightLookup) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!viewModel.canSave)
                }
            }
        }
    }

    /// Saves the flight, then keeps its reminder in sync: scheduling (or
    /// rescheduling by its stable identifier) a notification a lead time before
    /// departure. Scheduling is a safe no-op if notifications are denied
    /// (Req 8.2, 8.3).
    private func save() {
        guard let flight = viewModel.save(in: modelContext) else { return }
        let notifications = services.notifications
        Task { await notifications.sync(flight: flight) }
        dismiss()
    }

    // MARK: - Flight identity

    private var detailsSection: some View {
        Section("Flight") {
            TextField("Airline", text: $viewModel.airline)
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
            TextField("Flight Number", text: $viewModel.flightNumber)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
        }
    }

    // MARK: - Look up

    /// The "look up" action: fills the form from the flight number + departure
    /// date. On failure/offline it shows a clear message and leaves manual
    /// entry fully available (Req 2.4, 2.5).
    private var lookupSection: some View {
        Section {
            Button {
                Task { await viewModel.lookUp() }
            } label: {
                HStack {
                    Label("Look Up Flight", systemImage: "magnifyingglass")
                    Spacer()
                    if viewModel.isLookingUp {
                        ProgressView()
                    }
                }
            }
            .disabled(!viewModel.canLookUp)

            if let message = viewModel.lookupErrorMessage {
                Label(message, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Lookup failed. \(message)")
            } else if viewModel.lookupState == .filled {
                Label("Flight details filled in. Review and adjust as needed.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } footer: {
            Text("Enter a flight number to look up details, or fill the form in manually.")
        }
    }

    // MARK: - Departure

    private var departureSection: some View {
        Section("Departure") {
            PlaceSearchField(
                selection: $viewModel.departureAirport,
                prompt: "Departure airport"
            )
            .onChange(of: viewModel.departureAirport) { _, _ in
                viewModel.departureAirportChanged()
            }

            DatePicker(
                "Departs",
                selection: $viewModel.departureLocalTime,
                displayedComponents: [.date, .hourAndMinute]
            )

            TimeZonePicker(
                title: "Time Zone",
                selection: $viewModel.departureZoneIdentifier
            )

            zonePreview(
                instant: viewModel.departureInstant,
                zone: viewModel.departureTimeZone
            )
        }
    }

    // MARK: - Arrival

    private var arrivalSection: some View {
        Section("Arrival") {
            PlaceSearchField(
                selection: $viewModel.arrivalAirport,
                prompt: "Arrival airport"
            )
            .onChange(of: viewModel.arrivalAirport) { _, _ in
                viewModel.arrivalAirportChanged()
            }

            DatePicker(
                "Arrives",
                selection: $viewModel.arrivalLocalTime,
                displayedComponents: [.date, .hourAndMinute]
            )

            TimeZonePicker(
                title: "Time Zone",
                selection: $viewModel.arrivalZoneIdentifier
            )

            zonePreview(
                instant: viewModel.arrivalInstant,
                zone: viewModel.arrivalTimeZone
            )

            if viewModel.arrivalBeforeDeparture {
                Label(
                    "Arrival can't be before departure.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Optional details

    private var optionalDetailsSection: some View {
        Section("Details") {
            TextField("Terminal", text: $viewModel.terminal)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
            TextField("Gate", text: $viewModel.gate)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
            TextField("Booking Reference", text: $viewModel.bookingReference)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
            TextField("Seat", text: $viewModel.seat)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $viewModel.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Helpers

    /// Shows the instant as it will be displayed in the chosen zone, so the
    /// user can confirm the local time + zone label is what they expect.
    private func zonePreview(instant: Date, zone: TimeZone) -> some View {
        Label(
            DateHelpers.timeStringWithZone(instant, in: zone),
            systemImage: "clock"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Local time \(DateHelpers.timeStringWithZone(instant, in: zone))")
    }
}

// MARK: - Time-zone picker

/// A searchable picker over the available IANA time-zone identifiers, showing
/// the current UTC offset alongside each so the user can confirm the choice.
private struct TimeZonePicker: View {
    let title: String
    @Binding var selection: String

    private var currentLabel: String {
        TimeZonePicker.displayName(for: selection)
    }

    var body: some View {
        NavigationLink {
            TimeZoneList(selection: $selection)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(currentLabel)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// A friendly label like "Asia/Tokyo (GMT+9)".
    static func displayName(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let offset = zone.secondsFromGMT()
        let hours = offset / 3600
        let minutes = abs(offset / 60 % 60)
        let sign = hours >= 0 ? "+" : "-"
        let offsetLabel = minutes == 0
            ? String(format: "GMT%@%d", sign, abs(hours))
            : String(format: "GMT%@%d:%02d", sign, abs(hours), minutes)
        let name = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? identifier
        return "\(name) (\(offsetLabel))"
    }
}

/// The full searchable list of zones.
private struct TimeZoneList: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(identifiers, id: \.self) { identifier in
            Button {
                selection = identifier
                dismiss()
            } label: {
                HStack {
                    Text(TimeZonePicker.displayName(for: identifier))
                        .foregroundStyle(.primary)
                    Spacer()
                    if identifier == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query, prompt: "Search time zones")
        .navigationTitle("Time Zone")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Previews

#Preview("Create") {
    FlightEditView(mode: .create(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}

#Preview("Edit — Light") {
    FlightEditView(mode: .edit(SampleData.makeTokyoTrip().flights[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    FlightEditView(mode: .edit(SampleData.makeTokyoTrip().flights[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Large Type") {
    FlightEditView(mode: .edit(SampleData.makeTokyoTrip().flights[0]))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Look Up — Offline") {
    FlightEditView(mode: .create(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(
            \.appServices,
            AppServices(flightLookup: MockFlightLookupService(errorToThrow: .offline))
        )
}
