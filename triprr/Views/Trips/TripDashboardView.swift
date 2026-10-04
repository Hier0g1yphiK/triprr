//
//  TripDashboardView.swift
//  triprr
//
//  The trip dashboard: cover header, countdown, date range, a map of the
//  trip's places, and shortcuts to Flights, Stays, Itinerary and Suggestions.
//  Section destinations are placeholders until their respective tasks land.
//

import SwiftUI
import SwiftData
import MapKit

struct TripDashboardView: View {
    let trip: Trip

    @State private var viewModel = TripDashboardViewModel()
    @State private var isEditing = false

    private var coverColor: Color {
        trip.coverColorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                mapSection
                shortcutsSection
            }
            .padding()
        }
        .navigationTitle(trip.name.isEmpty ? "Trip" : trip.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            TripEditView(mode: .edit(trip))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(coverColor.gradient)
                .frame(height: 120)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.countdown(for: trip).label)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.25), in: Capsule())
                    }
                    .padding(12)
                }
                .overlay {
                    if let data = trip.coverImageData, let image = platformImage(data) {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

            Label(
                DateHelpers.dateRangeString(trip.startDate, trip.endDate, in: trip.primaryTimeZone),
                systemImage: "calendar"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if !trip.destinations.isEmpty {
                Label(
                    trip.destinations
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map(\.place.name)
                        .joined(separator: ", "),
                    systemImage: "mappin.and.ellipse"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapSection: some View {
        if let position = viewModel.mapPosition(for: trip) {
            Map(initialPosition: position) {
                ForEach(viewModel.annotatedPlaces(for: trip)) { place in
                    Marker(place.name, coordinate: place.coordinate)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Map of trip places")
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary)
                .frame(height: 120)
                .overlay {
                    Label("Add a destination to see it on the map", systemImage: "map")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DashboardShortcut(
                title: "Flights", systemImage: "airplane",
                count: trip.flights.count, tint: .blue
            ) {
                FlightListView(trip: trip)
            }
            DashboardShortcut(
                title: "Stays", systemImage: "bed.double",
                count: trip.stays.count, tint: .purple
            ) {
                StaysListView(trip: trip)
            }
            DashboardShortcut(
                title: "Bookings", systemImage: "ticket",
                count: trip.bookings.count, tint: .pink
            ) {
                BookingsListView(trip: trip)
            }
            DashboardShortcut(
                title: "Itinerary", systemImage: "list.bullet.rectangle",
                count: trip.activities.count, tint: .orange
            ) {
                DayItineraryView(trip: trip)
            }
            DashboardShortcut(
                title: "Suggestions", systemImage: "sparkles",
                count: nil, tint: .teal
            ) {
                SuggestionsView(trip: trip)
            }
            DashboardShortcut(
                title: "Notes & Links", systemImage: "note.text",
                count: trip.notes.count + trip.links.count, tint: .green
            ) {
                TripNotesView(trip: trip)
            }
        }
    }

    private func platformImage(_ data: Data) -> Image? {
#if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
#else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
#endif
    }
}

/// A tappable dashboard tile that navigates to a section.
private struct DashboardShortcut<Destination: View>: View {
    let title: String
    let systemImage: String
    let count: Int?
    let tint: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    if let count {
                        Text("\(count) item\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

#Preview("Dashboard — Light") {
    NavigationStack {
        TripDashboardView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Dashboard — Dark") {
    NavigationStack {
        TripDashboardView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Dashboard — Large Type") {
    NavigationStack {
        TripDashboardView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}
