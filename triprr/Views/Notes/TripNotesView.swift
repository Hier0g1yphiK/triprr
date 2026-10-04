//
//  TripNotesView.swift
//  triprr
//
//  A dedicated screen for a trip's notes and links, reachable from the trip
//  dashboard. Reuses the shared `NotesLinksSection` against the trip owner so
//  the add/edit/delete UI matches the activity editor exactly (Req 6.1–6.3).
//

import SwiftUI
import SwiftData

struct TripNotesView: View {
    let trip: Trip

    var body: some View {
        Form {
            NotesLinksSection(owner: .trip(trip))
        }
        .navigationTitle("Notes & Links")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview("Trip Notes — Light") {
    NavigationStack {
        TripNotesView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Trip Notes — Dark") {
    NavigationStack {
        TripNotesView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

#Preview("Trip Notes — Large Type") {
    NavigationStack {
        TripNotesView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .environment(\.dynamicTypeSize, .accessibility3)
}
