//
//  StayRow.swift
//  triprr
//
//  A single stay in the stays list. Check-in and check-out are shown in the
//  stay's local time zone with a visible zone label (Req 3.1, 10.3), along with
//  the kind, place and confirmation when present.
//

import SwiftUI

struct StayRow: View {
    let stay: Stay

    private var title: String {
        let trimmed = stay.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? stay.kind.displayName : trimmed
    }

    private var nights: Int {
        max(0, DateHelpers.dayCount(from: stay.checkIn, to: stay.checkOut, in: stay.effectiveTimeZone))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: stay.kind.symbolName)
                    .font(.headline)
                Spacer()
                if nights > 0 {
                    Text("\(nights) night\(nights == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                stayColumn(label: "Check-in", instant: stay.checkIn, alignment: .leading)

                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                stayColumn(label: "Check-out", instant: stay.checkOut, alignment: .trailing)
            }

            if let detail = detailLine {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private func stayColumn(
        label: String,
        instant: Date,
        alignment: HorizontalAlignment
    ) -> some View {
        let zone = stay.effectiveTimeZone
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(DateHelpers.dateString(instant, in: zone))
                .font(.subheadline.weight(.semibold))
            Text(DateHelpers.timeStringWithZone(instant, in: zone))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// A compact line of optional metadata (place / confirmation).
    private var detailLine: String? {
        var parts: [String] = []
        if let place = stay.place, !place.name.isEmpty { parts.append(place.name) }
        if let ref = stay.confirmationNumber, !ref.isEmpty { parts.append("Confirmation \(ref)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        let zone = stay.effectiveTimeZone
        let checkIn = DateHelpers.dateString(stay.checkIn, in: zone)
        let checkOut = DateHelpers.dateString(stay.checkOut, in: zone)
        return "\(title), \(stay.kind.displayName). Check-in \(checkIn). Check-out \(checkOut)."
    }
}

#Preview("Stay row") {
    List {
        StayRow(stay: SampleData.makeTokyoTrip().stays[0])
    }
}

#Preview("Stay row — Dark") {
    List {
        StayRow(stay: SampleData.makeTokyoTrip().stays[0])
    }
    .preferredColorScheme(.dark)
}

#Preview("Stay row — Large Type") {
    List {
        StayRow(stay: SampleData.makeTokyoTrip().stays[0])
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
