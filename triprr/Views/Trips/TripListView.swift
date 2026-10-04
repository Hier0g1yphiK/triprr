//
//  TripListView.swift
//  triprr
//
//  The trip list: trips grouped into Current / Upcoming / Past with an empty
//  state and create/delete entry points. Shared across iPhone (inside a
//  NavigationStack) and Mac (as the sidebar), driven by a selection binding.
//

import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var services
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]

    /// Selected trip, bound by the platform shell (sidebar selection on Mac,
    /// navigation value on iPhone).
    @Binding var selection: Trip?

    @State private var viewModel = TripListViewModel()
    @State private var editingTrip: Trip?
    @State private var isCreating = false
    @State private var tripPendingDeletion: Trip?

    var body: some View {
        Group {
            if trips.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("New Trip", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            TripEditView(mode: .create)
        }
        .sheet(item: $editingTrip) { trip in
            TripEditView(mode: .edit(trip))
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: Binding(
                get: { tripPendingDeletion != nil },
                set: { if !$0 { tripPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: tripPendingDeletion
        ) { trip in
            Button("Delete \"\(trip.name)\"", role: .destructive) {
                delete(trip)
            }
            Button("Cancel", role: .cancel) { tripPendingDeletion = nil }
        } message: { trip in
            Text(deletionMessage(for: trip))
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(viewModel.sections(from: trips)) { section in
                Section {
                    ForEach(section.trips) { trip in
                        row(for: trip)
                            .contextMenu {
                                Button("Edit") { editingTrip = trip }
                                Button("Delete", role: .destructive) {
                                    requestDelete(trip)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    requestDelete(trip)
                                }
                                Button("Edit") { editingTrip = trip }
                                    .tint(.blue)
                            }
                    }
                } header: {
                    Label(section.title, systemImage: section.symbolName)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for trip: Trip) -> some View {
#if os(macOS)
        // Sidebar selection drives the detail pane.
        TripRow(trip: trip).tag(trip)
#else
        // On iPhone, tapping pushes the dashboard via navigationDestination.
        NavigationLink(value: trip) {
            TripRow(trip: trip)
        }
#endif
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Trips Yet", systemImage: "suitcase.rolling")
        } description: {
            Text("Create your first trip to start planning flights, stays and things to do.")
        } actions: {
            Button {
                isCreating = true
            } label: {
                Text("New Trip")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Deletion

    private func requestDelete(_ trip: Trip) {
        if tripHasItems(trip) {
            tripPendingDeletion = trip
        } else {
            delete(trip)
        }
    }

    private func tripHasItems(_ trip: Trip) -> Bool {
        !(trip.flights.isEmpty && trip.stays.isEmpty && trip.bookings.isEmpty
          && trip.activities.isEmpty && trip.notes.isEmpty && trip.links.isEmpty
          && trip.destinations.isEmpty)
    }

    private func deletionMessage(for trip: Trip) -> String {
        let count = trip.flights.count + trip.stays.count + trip.bookings.count
            + trip.activities.count
        if count > 0 {
            return "This trip has \(count) item\(count == 1 ? "" : "s") that will also be deleted. This can't be undone."
        }
        return "This can't be undone."
    }

    private func delete(_ trip: Trip) {
        if selection == trip { selection = nil }

        // Cancel every pending reminder for the trip's flights and activities
        // before the cascade delete removes them (Req 8.3).
        let flightIDs = trip.flights.map(\.id)
        let activityIDs = trip.activities.map(\.id)
        let notifications = services.notifications
        Task {
            for id in flightIDs { await notifications.cancel(flightID: id) }
            for id in activityIDs { await notifications.cancel(activityID: id) }
        }

        modelContext.delete(trip)
        try? modelContext.save()
        tripPendingDeletion = nil
    }
}

#Preview("Trip list — Light") {
    NavigationStack {
        TripListView(selection: .constant(nil))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Trip list — Dark") {
    NavigationStack {
        TripListView(selection: .constant(nil))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Trip list — Large Type") {
    NavigationStack {
        TripListView(selection: .constant(nil))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Empty") {
    NavigationStack {
        TripListView(selection: .constant(nil))
    }
    .modelContainer(SampleData.emptyContainer())
    .environment(\.appServices, .mock)
}
