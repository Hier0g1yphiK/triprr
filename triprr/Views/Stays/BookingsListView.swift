//
//  BookingsListView.swift
//  triprr
//
//  Lists a trip's "other bookings" (restaurant reservations, tours, tickets,
//  transport) in start-time order, with a toolbar "+" to add, tap to edit,
//  swipe to delete, and a helpful empty state (Req 3.2, 3.5). Shared across
//  iPhone and Mac. Add and edit present the full `BookingEditView`.
//

import SwiftUI
import SwiftData

struct BookingsListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext

    @State private var isAdding = false
    @State private var editingBooking: Booking?

    /// Bookings ordered by their start instant.
    private var bookings: [Booking] {
        trip.bookings.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        Group {
            if bookings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Bookings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Booking", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            BookingEditView(mode: .create(trip))
        }
        .sheet(item: $editingBooking) { booking in
            BookingEditView(mode: .edit(booking))
        }
    }

    private var list: some View {
        List {
            ForEach(bookings) { booking in
                Button {
                    editingBooking = booking
                } label: {
                    BookingRow(booking: booking)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(booking)
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
            Label("No Bookings Yet", systemImage: "ticket")
        } description: {
            Text("Add restaurant reservations, tours, tickets or transport to keep every confirmation together.")
        } actions: {
            Button {
                isAdding = true
            } label: {
                Label("Add Booking", systemImage: "plus")
            }
        }
    }

    // MARK: - Delete

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets {
            delete(bookings[index])
        }
    }

    private func delete(_ booking: Booking) {
        modelContext.delete(booking)
        try? modelContext.save()
    }
}

#Preview("Bookings — Light") {
    NavigationStack {
        BookingsListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Bookings — Dark") {
    NavigationStack {
        BookingsListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Bookings — Large Type") {
    NavigationStack {
        BookingsListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Bookings — Empty") {
    NavigationStack {
        BookingsListView(trip: SampleData.makeUpcomingParisTrip())
    }
    .modelContainer(SampleData.emptyContainer())
    .environment(\.appServices, .mock)
}
