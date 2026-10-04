//
//  FlightRow.swift
//  triprr
//
//  A single flight in the flights list. Departure and arrival are each shown
//  in the local time zone of the relevant airport (derived from the airport's
//  Place), with a visible zone label (e.g. "09:30 JST"), per Req 2.2.
//

import SwiftUI

struct FlightRow: View {
    let flight: Flight

    private var flightTitle: String {
        let airline = flight.airline.trimmingCharacters(in: .whitespaces)
        let number = flight.flightNumber.trimmingCharacters(in: .whitespaces)
        switch (airline.isEmpty, number.isEmpty) {
        case (false, false): return "\(airline) \(number)"
        case (false, true): return airline
        case (true, false): return number
        case (true, true): return "Flight"
        }
    }

    private var departureDateLabel: String {
        DateHelpers.dateString(flight.scheduledDeparture, in: flight.departureTimeZone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(flightTitle, systemImage: "airplane")
                    .font(.headline)
                Spacer()
                Text(departureDateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                airportColumn(
                    code: flight.departureAirport.name,
                    time: flight.scheduledDeparture,
                    zone: flight.departureTimeZone,
                    alignment: .leading
                )

                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                airportColumn(
                    code: flight.arrivalAirport.name,
                    time: flight.scheduledArrival,
                    zone: flight.arrivalTimeZone,
                    alignment: .trailing
                )
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
    private func airportColumn(
        code: String,
        time: Date,
        zone: TimeZone,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(code.isEmpty ? "—" : code)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
            Text(DateHelpers.timeString(time, in: zone))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(DateHelpers.zoneAbbreviation(time, in: zone))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// A compact line of optional flight metadata (terminal / gate / seat / ref).
    private var detailLine: String? {
        var parts: [String] = []
        if let terminal = flight.terminal, !terminal.isEmpty { parts.append("Terminal \(terminal)") }
        if let gate = flight.gate, !gate.isEmpty { parts.append("Gate \(gate)") }
        if let seat = flight.seat, !seat.isEmpty { parts.append("Seat \(seat)") }
        if let ref = flight.bookingReference, !ref.isEmpty { parts.append("Ref \(ref)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityDescription: String {
        let dep = DateHelpers.timeStringWithZone(flight.scheduledDeparture, in: flight.departureTimeZone)
        let arr = DateHelpers.timeStringWithZone(flight.scheduledArrival, in: flight.arrivalTimeZone)
        let from = flight.departureAirport.name.isEmpty ? "departure airport" : flight.departureAirport.name
        let to = flight.arrivalAirport.name.isEmpty ? "arrival airport" : flight.arrivalAirport.name
        return "\(flightTitle). Departs \(from) at \(dep). Arrives \(to) at \(arr)."
    }
}

#Preview("Flight row") {
    List {
        FlightRow(flight: SampleData.makeTokyoTrip().flights[0])
    }
}

#Preview("Flight row — Dark") {
    List {
        FlightRow(flight: SampleData.makeTokyoTrip().flights[0])
    }
    .preferredColorScheme(.dark)
}

#Preview("Flight row — Large Type") {
    List {
        FlightRow(flight: SampleData.makeTokyoTrip().flights[0])
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
