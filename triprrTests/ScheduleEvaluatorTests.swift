//
//  ScheduleEvaluatorTests.swift
//  triprrTests
//
//  Unit tests for the pure `ScheduleEvaluator` (Req 4.5): classifying the gap
//  between consecutive day items as ok / tight / overlap against a configurable
//  buffer plus the travel time between them, the buffer boundary, the extra
//  lead time required before a flight, a missing travel estimate, and point vs
//  ranged entries. The evaluator is framework-free, so these run with plain
//  value fixtures and no simulator/network.
//

import Testing
import Foundation
@testable import triprr

struct ScheduleEvaluatorTests {

    // MARK: - Fixtures

    /// A fixed base instant so the tests are deterministic.
    private let base = Date(timeIntervalSinceReferenceDate: 0)

    /// Builds a ranged item ending `durationMinutes` after it starts.
    private func ranged(id: UUID = UUID(), startMinutes: Double, durationMinutes: Double, isFlight: Bool = false) -> ScheduleItem {
        let start = base.addingTimeInterval(startMinutes * 60)
        return ScheduleItem(
            id: id,
            start: start,
            end: start.addingTimeInterval(durationMinutes * 60),
            isFlight: isFlight
        )
    }

    /// Builds a point-in-time item (no end).
    private func point(id: UUID = UUID(), startMinutes: Double, isFlight: Bool = false) -> ScheduleItem {
        ScheduleItem(id: id, start: base.addingTimeInterval(startMinutes * 60), isFlight: isFlight)
    }

    // MARK: - ok / tight / overlap

    @Test func comfortableGapIsOK() {
        // A ends at 60; B starts at 120 → 60 min available. Travel 10 min,
        // buffer 15 min → required 10, slack 50 ≥ 15 → ok.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 120, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 10 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps.count == 1)
        #expect(gaps[0].afterEntryID == a.id)
        #expect(gaps[0].beforeEntryID == b.id)
        #expect(gaps[0].verdict == .ok)
        #expect(gaps[0].slackSeconds == 50 * 60)
        #expect(gaps[0].isWarning == false)
        #expect(gaps[0].warningText == nil)
    }

    @Test func travelPlusSmallSlackIsTight() {
        // A ends at 60; B starts at 90 → 30 min available. Travel 20 min →
        // slack 10 min, which is < 15 min buffer but ≥ 0 → tight.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 90, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 20 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].verdict == .tight)
        #expect(gaps[0].slackSeconds == 10 * 60)
        #expect(gaps[0].isWarning)
        #expect(gaps[0].warningText == "Tight connection")
    }

    @Test func nextStartsBeforeTravelAllowsIsOverlap() {
        // A ends at 60; B starts at 70 → 10 min available. Travel 20 min →
        // slack -10 min < 0 → overlap.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 70, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 20 * 60],
            buffer: .default
        )

        #expect(gaps[0].verdict == .overlap)
        #expect(gaps[0].slackSeconds == -10 * 60)
        #expect(gaps[0].warningText == "Overlaps previous")
    }

    @Test func nextStartsBeforePreviousEndsIsOverlapEvenWithoutTravel() {
        // B starts at 50, before A ends at 60 → negative available time → overlap
        // regardless of travel.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 50, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(items: [a, b], travelTimes: [:], buffer: .default)

        #expect(gaps[0].verdict == .overlap)
        #expect(gaps[0].slackSeconds == -10 * 60)
    }

    // MARK: - Buffer boundary

    @Test func slackExactlyAtBufferIsOK() {
        // Available 30 min, travel 15 min → slack 15 min == minimumGap → ok
        // (tight is strictly below the buffer).
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 90, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 15 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == 15 * 60)
        #expect(gaps[0].verdict == .ok)
    }

    @Test func slackJustUnderBufferIsTight() {
        // One second under the buffer flips ok → tight.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ScheduleItem(
            id: UUID(),
            start: base.addingTimeInterval(90 * 60 - 1),
            end: base.addingTimeInterval(120 * 60)
        )

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 15 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == 15 * 60 - 1)
        #expect(gaps[0].verdict == .tight)
    }

    @Test func zeroSlackIsTightNotOverlap() {
        // Available exactly equals travel → slack 0 → tight (boundary between
        // overlap and tight is at 0).
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 80, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 20 * 60],
            buffer: .default
        )

        #expect(gaps[0].slackSeconds == 0)
        #expect(gaps[0].verdict == .tight)
    }

    // MARK: - Before-a-flight lead time (Req 4.5)

    @Test func flightRequiresExtraLeadTime() {
        // 100 min available, 10 min travel. Without the flight lead this would
        // be ok (slack 90). With a 90-min flight lead the required time is 100,
        // leaving 0 slack → tight. The lead buffer is what flags it.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let flight = point(startMinutes: 160, isFlight: true)

        let buffer = ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        let gaps = ScheduleEvaluator.evaluate(
            items: [a, flight],
            travelTimes: [a.id: 10 * 60],
            buffer: buffer
        )

        #expect(gaps[0].nextIsFlight)
        #expect(gaps[0].slackSeconds == 0)
        #expect(gaps[0].verdict == .tight)
        #expect(gaps[0].warningText == "Tight connection to flight")
    }

    @Test func sameGapIsOKWhenNextIsNotAFlight() {
        // Identical timing/travel but the next item is not a flight: no lead
        // time, so slack is the full 90 min → ok. Confirms the lead buffer is
        // the only difference.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let notFlight = point(startMinutes: 160, isFlight: false)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, notFlight],
            travelTimes: [a.id: 10 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].nextIsFlight == false)
        #expect(gaps[0].slackSeconds == 90 * 60)
        #expect(gaps[0].verdict == .ok)
    }

    @Test func tooTightToMakeFlightIsOverlap() {
        // Only 30 min before the flight, 10 min travel + 90 min lead needed →
        // slack -70 → overlap, phrased for the flight.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let flight = point(startMinutes: 90, isFlight: true)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, flight],
            travelTimes: [a.id: 10 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].verdict == .overlap)
        #expect(gaps[0].warningText == "Too tight to make the flight")
    }

    // MARK: - Missing travel time

    @Test func missingTravelTimeTreatedAsZeroNoFalseWarning() {
        // No estimate for the leg. Available 30 min, travel treated as 0,
        // buffer 15 → slack 30 ≥ 15 → ok. A missing estimate never invents a
        // warning (Req 4.6).
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 90, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [:],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == 30 * 60)
        #expect(gaps[0].verdict == .ok)
    }

    @Test func missingTravelStillAppliesFlightLead() {
        // Even with no travel estimate, the flight lead still applies, so a
        // flight 30 min out with a 90-min lead is an overlap.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let flight = point(startMinutes: 90, isFlight: true)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, flight],
            travelTimes: [:],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == -60 * 60)
        #expect(gaps[0].verdict == .overlap)
    }

    // MARK: - Point vs ranged entries

    @Test func pointEntryEndsAtItsStart() {
        // A point item at 60 min, next starts at 90 → 30 min available (the
        // point's end is its start). Travel 10 → slack 20 ≥ 15 → ok.
        let a = point(startMinutes: 60)
        let b = ranged(startMinutes: 90, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 10 * 60],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == 20 * 60)
        #expect(gaps[0].verdict == .ok)
    }

    @Test func rangedEntryUsesItsEndNotItsStart() {
        // A ranged item [0, 60]; the gap is measured from its end (60), not its
        // start. Next at 70 with 0 travel → slack 10 < 15 → tight. If the start
        // had been used, available would be 70 and it would be ok — so this
        // asserts the end is used.
        let a = ranged(startMinutes: 0, durationMinutes: 60)
        let b = ranged(startMinutes: 70, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b],
            travelTimes: [a.id: 0],
            buffer: ScheduleBuffer(minimumGap: 15 * 60, flightLeadTime: 90 * 60)
        )

        #expect(gaps[0].slackSeconds == 10 * 60)
        #expect(gaps[0].verdict == .tight)
    }

    // MARK: - Multiple pairs / edge counts

    @Test func fewerThanTwoItemsProducesNoGaps() {
        #expect(ScheduleEvaluator.evaluate(items: [], travelTimes: [:], buffer: .default).isEmpty)
        let only = point(startMinutes: 0)
        #expect(ScheduleEvaluator.evaluate(items: [only], travelTimes: [:], buffer: .default).isEmpty)
    }

    @Test func producesOneGapPerConsecutivePairInOrder() {
        let a = ranged(startMinutes: 0, durationMinutes: 30)
        let b = ranged(startMinutes: 60, durationMinutes: 30)
        let c = ranged(startMinutes: 120, durationMinutes: 30)

        let gaps = ScheduleEvaluator.evaluate(
            items: [a, b, c],
            travelTimes: [a.id: 5 * 60, b.id: 5 * 60],
            buffer: .default
        )

        #expect(gaps.count == 2)
        #expect(gaps[0].afterEntryID == a.id)
        #expect(gaps[0].beforeEntryID == b.id)
        #expect(gaps[1].afterEntryID == b.id)
        #expect(gaps[1].beforeEntryID == c.id)
    }

    // MARK: - Default buffer

    @Test func defaultBufferIsFifteenMinutesAndNinetyMinuteFlightLead() {
        #expect(ScheduleBuffer.default.minimumGap == 15 * 60)
        #expect(ScheduleBuffer.default.flightLeadTime == 90 * 60)
    }
}
