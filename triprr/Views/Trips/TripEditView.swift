//
//  TripEditView.swift
//  triprr
//
//  Create or edit a trip: name, start/end dates with end-before-start
//  validation, destinations (via PlaceSearchField) and an optional colour or
//  image cover.
//

import SwiftUI
import SwiftData
import PhotosUI

struct TripEditView: View {
    enum Mode {
        case create
        case edit(Trip)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appServices) private var services

    let mode: Mode

    @State private var name: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var coverColorHex: String = Color.tripCoverPalette[0]
    @State private var coverImageData: Data?
    @State private var destinations: [Place] = []
    @State private var newDestination: Place?
    @State private var photoItem: PhotosPickerItem?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// End must not precede start.
    private var datesValid: Bool { endDate >= startDate }
    private var nameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canSave: Bool { nameValid && datesValid }
    private var hasCoverImage: Bool { coverImageData != nil }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                datesSection
                coverSection
                destinationsSection
            }
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
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
            .onChange(of: newDestination) { _, place in
                if let place {
                    destinations.append(place)
                    newDestination = nil
                }
            }
            .onChange(of: photoItem) { _, item in
                loadCoverImage(from: item)
            }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section("Trip") {
            TextField("Name", text: $name)
            if !nameValid {
                Label("Enter a name for the trip.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, newStart in
                    if endDate < newStart { endDate = newStart }
                }
            DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
            if !datesValid {
                Label("End date can't be before the start date.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var coverSection: some View {
        Section("Cover") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Color.tripCoverPalette, id: \.self) { hex in
                        Circle()
                            .fill((Color(hex: hex) ?? .accentColor).gradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if hex == coverColorHex && coverImageData == nil {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                coverColorHex = hex
                                coverImageData = nil
                            }
                            .accessibilityLabel("Cover colour")
                    }
                }
                .padding(.vertical, 4)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose Image", systemImage: "photo")
            }
            if hasCoverImage {
                Label("Image selected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.footnote)
                Button("Remove Image", role: .destructive) {
                    coverImageData = nil
                    photoItem = nil
                }
            }
        }
    }

    private var destinationsSection: some View {
        Section("Destinations") {
            ForEach(destinations) { place in
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(place.name)
                        if let address = place.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { destinations.remove(atOffsets: $0) }

            PlaceSearchField(selection: $newDestination, prompt: "Add a destination")
        }
    }

    // MARK: - Cover image

    @MainActor
    private func loadCoverImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            let data = try? await item.loadTransferable(type: Data.self)
            if let data {
                self.coverImageData = data
            }
        }
    }

    // MARK: - Load / Save

    private func load() {
        guard case let .edit(trip) = mode else { return }
        name = trip.name
        startDate = trip.startDate
        endDate = trip.endDate
        coverColorHex = trip.coverColorHex ?? Color.tripCoverPalette[0]
        coverImageData = trip.coverImageData
        destinations = trip.destinations
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.place)
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let trip = Trip(
                name: trimmedName,
                startDate: startDate,
                endDate: endDate,
                coverColorHex: coverImageData == nil ? coverColorHex : nil,
                coverImageData: coverImageData
            )
            modelContext.insert(trip)
            applyDestinations(to: trip)
        case .edit(let trip):
            trip.name = trimmedName
            trip.startDate = startDate
            trip.endDate = endDate
            trip.coverColorHex = coverImageData == nil ? coverColorHex : nil
            trip.coverImageData = coverImageData
            // Replace destinations with the edited set.
            for existing in trip.destinations {
                modelContext.delete(existing)
            }
            trip.destinations = []
            applyDestinations(to: trip)
        }

        try? modelContext.save()
        dismiss()
    }

    private func applyDestinations(to trip: Trip) {
        for (index, place) in destinations.enumerated() {
            let destination = Destination(place: place, sortOrder: index, trip: trip)
            modelContext.insert(destination)
        }
    }
}

#Preview("Create") {
    TripEditView(mode: .create)
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}

#Preview("Edit — Light") {
    TripEditView(mode: .edit(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    TripEditView(mode: .edit(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}

#Preview("Edit — Large Type") {
    TripEditView(mode: .edit(SampleData.makeTokyoTrip()))
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .environment(\.dynamicTypeSize, .accessibility3)
}
