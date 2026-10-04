//
//  FlightListView.swift
//  triprr
//
//  Lists a trip's flights in scheduled-departure order, each row showing
//  per-airport local times with zone labels (Req 2.2). A toolbar "+" adds a
//  flight, tapping a row edits it, and swipe deletes it — all persisted and
//  reflected immediately (Req 2.6). Shows a helpful empty state when the trip
//  has no flights yet. Shared across iPhone and Mac.
//

import SwiftUI
import SwiftData

struct FlightListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var services

    @State private var isAdding = false
    @State private var editingFlight: Flight?

    /// Flights ordered by their departure instant (UTC order matches
    /// chronological order regardless of per-airport zones).
    private var flights: [Flight] {
        trip.flights.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
    }

    var body: some View {
        Group {
            if flights.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Flights")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Flight", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            FlightEditView(mode: .create(trip))
        }
        .sheet(item: $editingFlight) { flight in
            FlightEditView(mode: .edit(flight))
        }
    }

    private var list: some View {
        List {
            ForEach(flights) { flight in
                Button {
                    editingFlight = flight
                } label: {
                    FlightRow(flight: flight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(flight)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: deleteAt)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Flights Yet", systemImage: "airplane")
        } description: {
            Text("Add a flight to see departure and arrival times in each airport's local time zone.")
        } actions: {
            Button {
                isAdding = true
            } label: {
                Label("Add Flight", systemImage: "plus")
            }
        }
    }

    // MARK: - Delete

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets {
            delete(flights[index])
        }
    }

    private func delete(_ flight: Flight) {
        // Cancel the pending reminder before the model id goes away (Req 8.3).
        let id = flight.id
        let notifications = services.notifications
        Task { await notifications.cancel(flightID: id) }

        modelContext.delete(flight)
        try? modelContext.save()
    }
}

#Preview("Flights — Light") {
    NavigationStack {
        FlightListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Flights — Dark") {
    NavigationStack {
        FlightListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Flights — Large Type") {
    NavigationStack {
        FlightListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Flights — Empty") {
    NavigationStack {
        FlightListView(trip: SampleData.makeUpcomingParisTrip())
    }
    .modelContainer(SampleData.emptyContainer())
    .environment(\.appServices, .mock)
}
