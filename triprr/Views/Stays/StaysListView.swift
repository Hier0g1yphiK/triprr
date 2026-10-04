//
//  StaysListView.swift
//  triprr
//
//  Lists a trip's stays in check-in order, each row showing check-in/out in the
//  stay's local time zone with a zone label. A toolbar "+" adds a stay, tapping
//  a row edits it, and swipe deletes it — all persisted and reflected
//  immediately (Req 3.1, 3.5). Shows a helpful empty state when the trip has no
//  stays yet. Shared across iPhone and Mac.
//

import SwiftUI
import SwiftData

struct StaysListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext

    @State private var isAdding = false
    @State private var editingStay: Stay?

    /// Stays ordered by their check-in instant (UTC order matches
    /// chronological order regardless of per-stay zones).
    private var stays: [Stay] {
        trip.stays.sorted { $0.checkIn < $1.checkIn }
    }

    var body: some View {
        Group {
            if stays.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Stays")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Stay", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            StayEditView(mode: .create(trip))
        }
        .sheet(item: $editingStay) { stay in
            StayEditView(mode: .edit(stay))
        }
    }

    private var list: some View {
        List {
            ForEach(stays) { stay in
                Button {
                    editingStay = stay
                } label: {
                    StayRow(stay: stay)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(stay)
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
            Label("No Stays Yet", systemImage: "bed.double")
        } description: {
            Text("Add a hotel or rental to keep its check-in, check-out and confirmation beside the trip.")
        } actions: {
            Button {
                isAdding = true
            } label: {
                Label("Add Stay", systemImage: "plus")
            }
        }
    }

    // MARK: - Delete

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets {
            delete(stays[index])
        }
    }

    private func delete(_ stay: Stay) {
        modelContext.delete(stay)
        try? modelContext.save()
    }
}

#Preview("Stays — Light") {
    NavigationStack {
        StaysListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Stays — Dark") {
    NavigationStack {
        StaysListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Stays — Large Type") {
    NavigationStack {
        StaysListView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Stays — Empty") {
    NavigationStack {
        StaysListView(trip: SampleData.makeUpcomingParisTrip())
    }
    .modelContainer(SampleData.emptyContainer())
    .environment(\.appServices, .mock)
}
