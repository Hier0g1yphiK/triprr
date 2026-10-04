//
//  SuggestionsView.swift
//  triprr
//
//  The smart-suggestions screen (Req 5). A request form captures how much time
//  the user has (a preset or a custom duration), when they start, the area to
//  explore (defaulting to the trip's primary destination), their interests and
//  their pace (Req 5.1). "Find suggestions" discovers candidates via the
//  injected `SuggestionService`, time-fits them with `SuggestionPlanner` (travel
//  backed by routing, straight-line fallback) in the view model, and shows the
//  result as a list of `SuggestionRow` carrying summary, duration,
//  distance-from-previous and category (Req 5.4). Each row adds the stop to the
//  day's itinerary in one tap, creating an `Activity` (Req 5.5).
//
//  The distinct view-model states drive what is shown: idle → the form,
//  loading → progress, loaded → the results list, empty → a no-results message,
//  error/offline → an error message with a retry action — empty and error are
//  kept visibly distinct (Req 5.6). Shared across iPhone and Mac.
//

import SwiftUI
import SwiftData

struct SuggestionsView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var services

    @State private var viewModel: SuggestionsViewModel

    init(trip: Trip) {
        self.trip = trip
        _viewModel = State(initialValue: SuggestionsViewModel(trip: trip))
    }

    /// Preview/testing seam: inject a pre-built view model.
    init(trip: Trip, viewModel: SuggestionsViewModel) {
        self.trip = trip
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            requestSection
            resultsSection
        }
        .navigationTitle("Suggestions")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            viewModel.use(suggestions: services.suggestions, routing: services.routing)
        }
    }

    // MARK: - Request form (Req 5.1)

    private var requestSection: some View {
        Group {
            Section("Available time") {
                Picker("How long", selection: $viewModel.timePreset) {
                    ForEach(AvailableTimePreset.allCases) { preset in
                        Label(preset.displayName, systemImage: preset.symbolName).tag(preset)
                    }
                }
                if viewModel.timePreset == .custom {
                    customDurationStepper
                }
            }

            Section("Start") {
                DatePicker(
                    "Start time",
                    selection: $viewModel.startTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                Label(
                    "Times shown in \(viewModel.areaTimeZone.identifier)",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Area") {
                if let area = viewModel.area {
                    Label(area.name, systemImage: "mappin.and.ellipse")
                } else {
                    Label("Add a destination to this trip to search for suggestions.",
                          systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Interests") {
                interestsGrid
                Text("Leave all off for a general mix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pace") {
                Picker("Pace", selection: $viewModel.pace) {
                    ForEach(Pace.allCases, id: \.self) { pace in
                        Label(pace.displayName, systemImage: pace.symbolName).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    Task { await viewModel.requestSuggestions() }
                } label: {
                    HStack {
                        Spacer()
                        Label("Find suggestions", systemImage: "sparkles")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!viewModel.canRequest)
            }
        }
    }

    private var customDurationStepper: some View {
        let hours = Binding<Double>(
            get: { viewModel.customDuration / 3600 },
            set: { viewModel.customDuration = $0 * 3600 }
        )
        return Stepper(value: hours, in: 1...12, step: 0.5) {
            Text("Custom: \(SuggestionRow.durationLabel(for: viewModel.customDuration))")
        }
    }

    private var interestsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Interest.allCases, id: \.self) { interest in
                InterestChip(
                    interest: interest,
                    isSelected: viewModel.isSelected(interest)
                ) {
                    viewModel.toggle(interest)
                }
            }
        }
    }

    // MARK: - Results (states: loading / loaded / empty / error — Req 5.6)

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()

        case .loading:
            Section("Suggestions") {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding things to do…")
                        .foregroundStyle(.secondary)
                }
            }

        case let .loaded(items):
            Section {
                ForEach(items) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        timeZone: viewModel.areaTimeZone,
                        isAdded: viewModel.isAdded(suggestion)
                    ) {
                        viewModel.addToDay(suggestion, trip: trip, context: modelContext)
                    }
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("^[\(items.count) stop](inflect: true) that fit your time, in visiting order.")
            }

        case .empty:
            Section {
                SuggestionsEmptyState()
            }

        case let .error(message):
            Section {
                SuggestionsErrorState(message: message, canRetry: viewModel.canRequest) {
                    Task { await viewModel.requestSuggestions() }
                }
            }
        }
    }
}

// MARK: - Distinct empty vs error states (Req 5.6)

/// The no-results state: a search ran but nothing fit. Deliberately distinct
/// from the error state — a neutral "search" glyph, a "none found" message, and
/// guidance to widen the search, with no retry button (retrying the same search
/// would find nothing again).
struct SuggestionsEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No suggestions found", systemImage: "sparkle.magnifyingglass")
        } description: {
            Text("Nothing matched for this area and time. Try widening your interests, allowing more time, or a different start.")
        }
    }
}

/// The error/offline state: generation failed or the device is offline.
/// Deliberately distinct from the empty state — a warning/offline glyph, a
/// "couldn't load" message carrying the specific error, and a retry action
/// (the request can succeed on a later attempt).
struct SuggestionsErrorState: View {
    let message: String
    let canRetry: Bool
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load suggestions", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .disabled(!canRetry)
        }
    }
}

/// A toggleable interest chip for the multi-select (Req 5.1).
private struct InterestChip: View {
    let interest: Interest
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(interest.displayName, systemImage: interest.symbolName)
                .font(.subheadline)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(interest.displayName)
    }
}

// MARK: - Previews

#Preview("Form — Idle") {
    NavigationStack {
        SuggestionsView(trip: SampleData.currentTrip(in: SampleData.container.mainContext))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
}

#Preview("Loaded — Light") {
    NavigationStack {
        SuggestionsView.loadedPreview(colorScheme: .light)
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.light)
}

#Preview("Loaded — Dark") {
    NavigationStack {
        SuggestionsView.loadedPreview(colorScheme: .dark)
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
    .preferredColorScheme(.dark)
}

// The empty and error states as separate, focused previews so the visual
// distinction (Req 5.6) is checkable at a glance in a static snapshot —
// rendering the result presentation directly rather than scrolling past the
// request form.

#Preview("State — Empty") {
    SuggestionsEmptyState()
}

#Preview("State — Error/Offline") {
    SuggestionsErrorState(
        message: SuggestionError.offline.message,
        canRetry: true,
        onRetry: {}
    )
}

#Preview("State — Error (dark)") {
    SuggestionsErrorState(
        message: SuggestionError.failed.message,
        canRetry: true,
        onRetry: {}
    )
    .preferredColorScheme(.dark)
}

// The empty/error states embedded in the full screen (seeded synchronously).

#Preview("Screen — Empty") {
    NavigationStack {
        SuggestionsView.statePreview(.empty)
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
}

#Preview("Screen — Error/Offline") {
    NavigationStack {
        SuggestionsView.statePreview(.error(SuggestionError.offline.message))
    }
    .modelContainer(SampleData.container)
    .environment(\.appServices, .mock)
}

extension SuggestionsView {
    /// A preview that has already run a successful request against the mock, so
    /// the loaded results list is visible without interaction.
    @MainActor
    fileprivate static func loadedPreview(colorScheme: ColorScheme) -> some View {
        let trip = SampleData.currentTrip(in: SampleData.container.mainContext)
        let vm = SuggestionsViewModel(trip: trip, suggestions: MockSuggestionService())
        return SuggestionsView(trip: trip, viewModel: vm)
            .task { await vm.requestSuggestions() }
    }

    /// A preview that lands in a given terminal state synchronously, so the
    /// state's result section (empty message, or error with retry) is visible
    /// in a static snapshot — keeping the empty vs error distinction checkable
    /// without waiting on an async request (Req 5.6).
    @MainActor
    fileprivate static func statePreview(_ state: SuggestionsViewModel.LoadState) -> some View {
        let trip = SampleData.currentTrip(in: SampleData.container.mainContext)
        let vm = SuggestionsViewModel(trip: trip, suggestions: MockSuggestionService())
        vm.setStateForPreview(state)
        return SuggestionsView(trip: trip, viewModel: vm)
    }
}
