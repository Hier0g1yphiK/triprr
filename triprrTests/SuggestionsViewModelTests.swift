//
//  SuggestionsViewModelTests.swift
//  triprrTests
//
//  Unit tests for the suggestions view model's request-form state and its load
//  state machine. The focus is that `loaded`, `empty` and `error` are DISTINCT
//  states: zero candidates must land in `empty`, while a thrown/offline failure
//  must land in `error` (Req 5.6). Also covers available-time preset resolution
//  and the default area coming from the trip's primary destination (Req 5.1).
//

import Testing
import Foundation
@testable import triprr

@MainActor
struct SuggestionsViewModelTests {

    private var tokyoArea: Place {
        Place(
            name: "Tokyo",
            latitude: 35.6812, longitude: 139.7671,
            address: "Tokyo, Japan",
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    // MARK: - Load state machine (Req 5.6)

    @Test func startsIdle() {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())
        #expect(vm.state == .idle)
    }

    @Test func successLoadsSuggestions() async {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())

        await vm.requestSuggestions()

        guard case let .loaded(items) = vm.state else {
            Issue.record("Expected .loaded, got \(vm.state)")
            return
        }
        #expect(!items.isEmpty)
        #expect(vm.loadedSuggestions.count == items.count)
        #expect(vm.errorMessage == nil)
    }

    @Test func noResultsIsEmptyNotError() async {
        let vm = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(returnsEmpty: true)
        )

        await vm.requestSuggestions()

        #expect(vm.state == .empty)
        #expect(vm.errorMessage == nil)
        #expect(vm.loadedSuggestions.isEmpty)
    }

    @Test func offlineIsErrorNotEmpty() async {
        let vm = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(errorToThrow: .offline)
        )

        await vm.requestSuggestions()

        guard case .error = vm.state else {
            Issue.record("Expected .error, got \(vm.state)")
            return
        }
        #expect(vm.errorMessage != nil)
        #expect(vm.state != .empty)
    }

    @Test func failureIsError() async {
        let vm = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(errorToThrow: .failed)
        )

        await vm.requestSuggestions()

        #expect(vm.errorMessage == SuggestionError.failed.message)
    }

    @Test func emptyAndErrorStatesAreDistinct() async {
        let empty = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(returnsEmpty: true)
        )
        let errored = SuggestionsViewModel(
            area: tokyoArea,
            suggestions: MockSuggestionService(errorToThrow: .offline)
        )

        await empty.requestSuggestions()
        await errored.requestSuggestions()

        #expect(empty.state == .empty)
        if case .error = errored.state {} else {
            Issue.record("Expected errored VM in .error state")
        }
        #expect(empty.state != errored.state)
    }

    // MARK: - Request form (Req 5.1)

    @Test func cannotRequestWithoutArea() {
        let vm = SuggestionsViewModel(area: nil, suggestions: MockSuggestionService())
        #expect(vm.canRequest == false)
    }

    @Test func requestWithoutAreaDoesNothing() async {
        let vm = SuggestionsViewModel(area: nil, suggestions: MockSuggestionService())
        await vm.requestSuggestions()
        #expect(vm.state == .idle)
    }

    @Test func presetResolvesAvailableTime() {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())
        vm.timePreset = .fullDay
        #expect(vm.resolvedAvailableTime == 8 * 3600)
        vm.timePreset = .coupleHours
        #expect(vm.resolvedAvailableTime == 2 * 3600)
    }

    @Test func customPresetUsesCustomDuration() {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())
        vm.timePreset = .custom
        vm.customDuration = 3 * 3600
        #expect(vm.resolvedAvailableTime == 3 * 3600)
    }

    @Test func interestToggleAddsAndRemoves() {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())
        #expect(vm.isSelected(.food) == false)
        vm.toggle(.food)
        #expect(vm.isSelected(.food) == true)
        vm.toggle(.food)
        #expect(vm.isSelected(.food) == false)
    }

    @Test func interestsFilterResults() async {
        let vm = SuggestionsViewModel(area: tokyoArea, suggestions: MockSuggestionService())
        vm.toggle(.food)

        await vm.requestSuggestions()

        #expect(vm.loadedSuggestions.allSatisfy { $0.category == .food })
        #expect(!vm.loadedSuggestions.isEmpty)
    }

    @Test func defaultsAreaFromTripPrimaryDestination() {
        let trip = SampleData.makeTokyoTrip()
        let vm = SuggestionsViewModel(trip: trip, suggestions: MockSuggestionService())
        #expect(vm.area?.name == "Tokyo Station Hotel")
    }

    @Test func mockIsDeterministic() async throws {
        let service = MockSuggestionService()
        let request = SuggestionRequest(
            area: tokyoArea,
            start: Date(),
            available: 4 * 3600,
            interests: [],
            pace: .relaxed
        )
        let first = try await service.suggestions(for: request)
        let second = try await service.suggestions(for: request)
        #expect(first.map(\.id) == second.map(\.id))
    }
}
