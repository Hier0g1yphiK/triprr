//
//  BookingRow.swift
//  triprr
//
//  A single "other booking" (restaurant, tour, ticket, transport, …) in the
//  bookings list. Its time (or time range) is shown in the booking's local time
//  zone with a visible zone label (Req 3.2, 10.3), along with the kind, place
//  and confirmation when present.
//

import SwiftUI

struct BookingRow: View {
    let booking: Booking

    private var title: String {
        let trimmed = booking.title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? booking.kind.displayName : trimmed
    }

    private var timeLabel: String {
        let zone = booking.effectiveTimeZone
        let start = DateHelpers.timeStringWithZone(booking.startDate, in: zone)
        if let end = booking.endDate {
            let endLabel = DateHelpers.isSameDay(booking.startDate, end, in: zone)
                ? DateHelpers.timeString(end, in: zone)
                : DateHelpers.timeStringWithZone(end, in: zone)
            return "\(start) – \(endLabel)"
        }
        return start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: booking.kind.symbolName)
                    .font(.headline)
                Spacer()
                Text(DateHelpers.dateString(booking.startDate, in: booking.effectiveTimeZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(timeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let detail = detailLine {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(booking.kind.displayName). \(timeLabel).")
    }

    /// A compact line of optional metadata (place / confirmation).
    private var detailLine: String? {
        var parts: [String] = []
        if let place = booking.place, !place.name.isEmpty { parts.append(place.name) }
        if let ref = booking.confirmationNumber, !ref.isEmpty { parts.append("Confirmation \(ref)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview("Booking row") {
    List {
        BookingRow(booking: SampleData.makeTokyoTrip().bookings[0])
    }
}

#Preview("Booking row — Dark") {
    List {
        BookingRow(booking: SampleData.makeTokyoTrip().bookings[0])
    }
    .preferredColorScheme(.dark)
}

#Preview("Booking row — Large Type") {
    List {
        BookingRow(booking: SampleData.makeTokyoTrip().bookings[0])
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
