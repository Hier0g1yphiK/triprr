//
//  DayMapView.swift
//  triprr
//
//  A map of a single day's placed itinerary items, plotted as a route in
//  itinerary (time) order (Req 4.7). Each placed item gets a numbered marker in
//  sequence, and a line connects them in order so the day reads as a path. An
//  "Open in Apple Maps" button hands the ordered stops to the Apple Maps app so
//  the traveller gets live, turn-by-turn multi-stop directions there.
//
//  The ordered placed entries come from `DayItineraryViewModel`, which already
//  produces the day's chronological timeline and knows which entries carry a
//  `Place`. Entries without a place are simply absent from the route. The
//  trivial cases are handled: an empty day shows a helpful state, a single stop
//  shows just that pin (and "Open in Apple Maps" opens that one location),
//  while two or more stops draw and open a connected route. Shared across
//  iPhone and Mac — the `Map` and `MKMapItem.openMaps` both work on macOS.
//

import SwiftUI
import SwiftData
import MapKit

struct DayMapView: View {
    let viewModel: DayItineraryViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition = .automatic

    /// The ordered placed stops for the selected day — the route in time order.
    private var stops: [Stop] {
        viewModel.placedEntriesForSelectedDay.enumerated().map { index, entry in
            Stop(number: index + 1, entry: entry, place: entry.place!)
        }
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        stops.map { $0.place.coordinate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if stops.isEmpty {
                    emptyState
                } else {
                    map
                }
            }
            .navigationTitle(mapTitle)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openInAppleMaps()
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                    }
                    .disabled(stops.isEmpty)
                }
            }
        }
    }

    private var mapTitle: String {
        viewModel.selectedDayStart.map(viewModel.dayLabel) ?? "Day Map"
    }

    // MARK: - Map

    private var map: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                // Draw the route connecting the stops in order (two or more).
                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // A numbered marker per placed stop, in itinerary order.
                ForEach(stops) { stop in
                    Marker(
                        "\(stop.number). \(stop.entry.title)",
                        systemImage: stop.entry.symbolName,
                        coordinate: stop.place.coordinate
                    )
                    .tint(Color.accentColor)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onAppear { frameRoute() }

            routeLegend
        }
    }

    /// A compact ordered list beneath the map so the route reads as a sequence
    /// even for VoiceOver and when markers overlap at low zoom.
    private var routeLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stops) { stop in
                    HStack(spacing: 6) {
                        Text("\(stop.number)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.tint))
                        Text(stop.entry.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Stop \(stop.number): \(stop.entry.title)")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No places to map", systemImage: "mappin.slash")
        } description: {
            Text("Add activities, stays or bookings with a location to see this day as a route.")
        }
    }

    // MARK: - Camera

    /// Frames the camera to show all of the day's stops.
    private func frameRoute() {
        let coordinates = routeCoordinates
        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1 {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinates[0],
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
            return
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Pad the span so markers aren't flush against the map edges.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.02)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Apple Maps

    /// Opens the day's route in the Apple Maps app with the ordered stops. For
    /// two or more stops, `MKMapItem.openMaps(with:launchOptions:)` reliably
    /// presents a multi-stop route in Maps on both iOS and macOS. For a single
    /// stop it just opens that location. A route of named map items is more
    /// robust than a hand-built `maps.apple.com` URL for several stops, so we
    /// prefer it here (Req 4.7).
    private func openInAppleMaps() {
        let mapItems = stops.map { stop -> MKMapItem in
            let item = stop.place.mapItem
            item.name = stop.entry.title
            return item
        }
        guard !mapItems.isEmpty else { return }

        if mapItems.count == 1 {
            mapItems[0].openInMaps()
            return
        }

        let launchOptions: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: directionsMode
        ]
        MKMapItem.openMaps(with: mapItems, launchOptions: launchOptions)
    }

    /// The Apple Maps directions mode matching the day's default travel mode.
    private var directionsMode: String {
        switch DayItineraryViewModel.defaultTravelMode {
        case .automobile: MKLaunchOptionsDirectionsModeDriving
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        }
    }
}

// MARK: - Stop

/// A single placed stop on the day's route: its order number, the originating
/// timeline entry and its place.
private struct Stop: Identifiable {
    let number: Int
    let entry: TimelineEntry
    let place: Place

    var id: UUID { entry.id }
}

// MARK: - Previews

private func dayMapPreviewModel() -> DayItineraryViewModel {
    let trip = SampleData.currentTrip(in: SampleData.container.mainContext)
    let model = DayItineraryViewModel(trip: trip)
    // Select the day that holds the Tokyo activities (breakfast / teamLab /
    // temple) so the preview shows a multi-stop route.
    if let day = model.dayStarts.first(where: { start in
        !model.entries(forDayStarting: start).filter { $0.place != nil }.isEmpty
            && model.entries(forDayStarting: start).filter { $0.place != nil }.count >= 2
    }) {
        model.selectedDayStart = day
    }
    return model
}

#Preview("Day Map — Light") {
    DayMapView(viewModel: dayMapPreviewModel())
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.light)
}

#Preview("Day Map — Dark") {
    DayMapView(viewModel: dayMapPreviewModel())
        .modelContainer(SampleData.container)
        .environment(\.appServices, .mock)
        .preferredColorScheme(.dark)
}
