//
//  RootView.swift
//  triprr
//
//  The top-level view and the single place the UI branches by platform:
//  a sidebar + detail split on Mac, a tab bar + navigation stack on iPhone.
//  Both present the same trip hierarchy and share every downstream screen.
//

import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
#if os(macOS)
        MacRootView()
#else
        PhoneRootView()
#endif
    }
}

// MARK: - macOS: Today + trips (sidebar + detail)

#if os(macOS)
private struct MacRootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    TodayView()
                }
            }
            Tab("Trips", systemImage: "airplane") {
                MacTripsSplitView()
            }
        }
    }
}

/// The Mac trips experience: a sidebar of trips with the selected trip's
/// dashboard in the detail area (Req 9.1).
private struct MacTripsSplitView: View {
    @State private var selection: Trip?

    var body: some View {
        NavigationSplitView {
            TripListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            NavigationStack {
                if let selection {
                    TripDashboardView(trip: selection)
                } else {
                    ContentUnavailableView(
                        "Select a Trip",
                        systemImage: "suitcase.rolling",
                        description: Text("Choose a trip from the sidebar, or create a new one.")
                    )
                }
            }
        }
    }
}
#endif

// MARK: - iOS: tabs + navigation stack

#if !os(macOS)
private struct PhoneRootView: View {
    @State private var tripSelection: Trip?

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    TodayView()
                }
            }
            Tab("Trips", systemImage: "airplane") {
                NavigationStack {
                    TripListView(selection: $tripSelection)
                        .navigationDestination(for: Trip.self) { trip in
                            TripDashboardView(trip: trip)
                        }
                }
            }
        }
    }
}
#endif

#Preview {
    RootView()
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
}
