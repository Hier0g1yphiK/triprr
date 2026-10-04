//
//  PlaceSearchField.swift
//  triprr
//
//  A reusable control for searching and selecting a Place via MapKit. Used by
//  trip destinations, activities, stays and bookings. On selection it resolves
//  the place's time zone (best-effort) so local-time display is correct.
//

import SwiftUI
import MapKit

struct PlaceSearchField: View {
    /// The currently selected place, if any.
    @Binding var selection: Place?
    /// Prompt shown when nothing is selected.
    var prompt: String = "Search for a place"

    @Environment(\.appServices) private var services

    @State private var query: String = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchError: PlaceSearchError?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection {
                selectedRow(selection)
            }

            TextField(prompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.words)
#endif
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }

            if isSearching {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Searching…").foregroundStyle(.secondary).font(.footnote)
                }
            } else if let searchError {
                errorRow(searchError)
            } else if !results.isEmpty {
                resultsList
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func selectedRow(_ place: Place) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body)
                if let address = place.address {
                    Text(address).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                selection = nil
                query = ""
                results = []
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selected place")
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(results) { place in
                Button {
                    select(place)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.body).foregroundStyle(.primary)
                        if let address = place.address {
                            Text(address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                if place.id != results.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorRow(_ error: PlaceSearchError) -> some View {
        Label(
            error == .offline ? "You're offline. Connect to search places." : "Couldn't search right now.",
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: - Search

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        searchError = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // Debounce.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            await runSearch(trimmed)
        }
    }

    private func runSearch(_ text: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await services.placeSearch.search(query: text, region: nil)
            if Task.isCancelled { return }
            results = found
            searchError = found.isEmpty ? nil : nil
        } catch let error as PlaceSearchError {
            if Task.isCancelled { return }
            results = []
            searchError = error
        } catch {
            if Task.isCancelled { return }
            results = []
            searchError = .failed
        }
    }

    private func select(_ place: Place) {
        results = []
        query = ""
        selection = place
        // Resolve the time zone in the background if missing.
        if place.timeZoneIdentifier == nil {
            Task {
                let resolved = await services.timeZoneResolver.resolvingTimeZone(for: place)
                if selection?.id == resolved.id {
                    selection = resolved
                }
            }
        }
    }
}

#Preview("Place search") {
    @Previewable @State var place: Place? = nil
    Form {
        PlaceSearchField(selection: $place, prompt: "Search destination")
    }
    .environment(\.appServices, .mock)
}
