//
//  TripRow.swift
//  triprr
//
//  A single row in the trip list: cover swatch, name, destinations, date range
//  and a countdown badge.
//

import SwiftUI

struct TripRow: View {
    let trip: Trip

    private var coverColor: Color {
        trip.coverColorHex.flatMap(Color.init(hex:)) ?? .accentColor
    }

    private var countdown: TripCountdown {
        TripCountdown.make(
            start: trip.startDate,
            end: trip.endDate,
            timeZone: trip.primaryTimeZone
        )
    }

    private var destinationSummary: String {
        let names = trip.destinations
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.place.name)
        return names.isEmpty ? "No destination yet" : names.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            cover
            // Reflow at large Dynamic Type: keep the countdown badge trailing
            // when it fits, otherwise stack it under the trip details so the
            // badge never squeezes or truncates the name.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    details
                    Spacer(minLength: 8)
                    countdownBadge
                }
                VStack(alignment: .leading, spacing: 6) {
                    details
                    countdownBadge
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(trip.name.isEmpty ? "Untitled Trip" : trip.name)
                .font(.headline)
                .lineLimit(1)
            Text(destinationSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(DateHelpers.dateRangeString(trip.startDate, trip.endDate, in: trip.primaryTimeZone))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countdownBadge: some View {
        Text(countdown.label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(coverColor.opacity(0.15), in: Capsule())
            .foregroundStyle(coverColor)
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(coverColor.gradient)
            .frame(width: 46, height: 46)
            .overlay {
                if let data = trip.coverImageData, let image = platformImage(data) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "suitcase.rolling.fill")
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .accessibilityHidden(true)
    }

    private func platformImage(_ data: Data) -> Image? {
#if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
#else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
#endif
    }
}

#Preview("Trip rows — Light") {
    List {
        TripRow(trip: SampleData.makeTokyoTrip())
        TripRow(trip: SampleData.makeUpcomingParisTrip())
        TripRow(trip: SampleData.makePastTrip())
    }
    .preferredColorScheme(.light)
}

#Preview("Trip rows — Dark") {
    List {
        TripRow(trip: SampleData.makeTokyoTrip())
        TripRow(trip: SampleData.makeUpcomingParisTrip())
        TripRow(trip: SampleData.makePastTrip())
    }
    .preferredColorScheme(.dark)
}

#Preview("Trip rows — Large Type") {
    List {
        TripRow(trip: SampleData.makeTokyoTrip())
        TripRow(trip: SampleData.makeUpcomingParisTrip())
        TripRow(trip: SampleData.makePastTrip())
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
