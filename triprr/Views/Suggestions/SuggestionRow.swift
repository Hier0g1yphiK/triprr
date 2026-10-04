//
//  SuggestionRow.swift
//  triprr
//
//  A single row in the suggestions list. Shows the suggested stop's title (the
//  place name) and short summary, its category as an SF Symbol plus name, the
//  estimated visit duration, and — when the planner assigned it — the distance
//  from the previous stop and the planned arrival time (Req 5.4). A trailing
//  one-tap "Add" button creates the activity on the day; once added the row
//  shows a clear "Added" checkmark and disables, so the action reads as done
//  (Req 5.5). The whole row carries a single combined accessibility label so
//  VoiceOver announces it as one coherent suggestion.
//

import SwiftUI

struct SuggestionRow: View {
    let suggestion: Suggestion
    /// The zone to render planned times in (the area's local zone).
    let timeZone: TimeZone
    /// Whether this suggestion has already been added to the day.
    let isAdded: Bool
    /// One-tap add action.
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            categoryIcon
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.place.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if !suggestion.summary.isEmpty {
                    Text(suggestion.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                metadata
            }
            Spacer(minLength: 8)
            addButton
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isAdded ? "Added to the day" : "Double tap to add to the day")
    }

    // MARK: - Pieces

    private var categoryIcon: some View {
        Image(systemName: suggestion.category.symbolName)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 32, height: 32)
            .background(.tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { metadataLabels }
            VStack(alignment: .leading, spacing: 4) { metadataLabels }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(suggestion.category.displayName, systemImage: suggestion.category.symbolName)
        Label(durationText, systemImage: "clock")
        if let distanceText {
            Label(distanceText, systemImage: "figure.walk")
        }
        if let arrivalText {
            Label(arrivalText, systemImage: "mappin.and.ellipse")
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if isAdded {
            Label("Added", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        } else {
            Button(action: onAdd) {
                Label("Add", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Formatting

    /// A short visit-duration label, e.g. "1 hr 30 min" or "45 min".
    private var durationText: String {
        Self.durationLabel(for: suggestion.estimatedVisitDuration)
    }

    /// The distance-from-previous label (Req 5.4), nil for the first stop.
    private var distanceText: String? {
        guard let distance = suggestion.distanceFromPrevious else { return nil }
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(0...1))
            )
        )
    }

    /// The planned arrival time in the area's zone, nil until planned.
    private var arrivalText: String? {
        guard let arrival = suggestion.arrivalTime else { return nil }
        return DateHelpers.timeString(arrival, in: timeZone)
    }

    /// A single combined label so VoiceOver reads the row as one suggestion.
    private var accessibilityLabel: String {
        var parts: [String] = [
            suggestion.place.name,
            suggestion.category.displayName,
            "about \(durationText)",
        ]
        if let distanceText {
            parts.append("\(distanceText) from the previous stop")
        }
        if let arrivalText {
            parts.append("arriving \(arrivalText)")
        }
        if isAdded {
            parts.append("added")
        }
        return parts.joined(separator: ", ")
    }

    /// Formats a duration in whole minutes/hours, e.g. "45 min", "1 hr 30 min".
    static func durationLabel(for seconds: TimeInterval) -> String {
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes) min"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}

#Preview("Rows — Light") {
    SuggestionRowPreview()
        .preferredColorScheme(.light)
}

#Preview("Rows — Dark") {
    SuggestionRowPreview()
        .preferredColorScheme(.dark)
}

#Preview("Rows — Large Type") {
    SuggestionRowPreview()
        .environment(\.dynamicTypeSize, .accessibility3)
}

private struct SuggestionRowPreview: View {
    private var area: Place {
        Place(
            name: "Tokyo",
            latitude: 35.6812, longitude: 139.7671,
            timeZoneIdentifier: "Asia/Tokyo"
        )
    }

    private var samples: [Suggestion] {
        let zone = "Asia/Tokyo"
        let start = Date()
        return [
            Suggestion(
                place: Place(name: "City Art Museum", latitude: 35.685, longitude: 139.77,
                             address: "Chiyoda, Tokyo", timeZoneIdentifier: zone),
                category: .museum,
                summary: "A compact collection worth an hour or two.",
                estimatedVisitDuration: 90 * 60,
                arrivalTime: start,
                departureTime: start.addingTimeInterval(90 * 60)
            ),
            Suggestion(
                place: Place(name: "Old Town Landmark", latitude: 35.714, longitude: 139.79,
                             address: "Asakusa, Tokyo", timeZoneIdentifier: zone),
                category: .landmark,
                summary: "The classic photo stop in the historic quarter.",
                estimatedVisitDuration: 45 * 60,
                distanceFromPrevious: 3200,
                arrivalTime: start.addingTimeInterval(120 * 60),
                departureTime: start.addingTimeInterval(165 * 60)
            ),
        ]
    }

    var body: some View {
        List {
            SuggestionRow(suggestion: samples[0], timeZone: area.timeZone ?? .current,
                          isAdded: false, onAdd: {})
            SuggestionRow(suggestion: samples[1], timeZone: area.timeZone ?? .current,
                          isAdded: true, onAdd: {})
        }
    }
}
