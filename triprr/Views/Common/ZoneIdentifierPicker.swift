//
//  ZoneIdentifierPicker.swift
//  triprr
//
//  A reusable, searchable picker over IANA time-zone identifiers, showing each
//  zone's current UTC offset so the user can confirm the choice. Used by the
//  stay and booking editors (and available to any editor that needs to confirm
//  the zone an instant is displayed in).
//

import SwiftUI

/// A form row that presents a searchable list of time zones and binds the
/// chosen IANA identifier.
struct ZoneIdentifierPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        NavigationLink {
            TimeZoneList(selection: $selection)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(ZoneIdentifierPicker.displayName(for: selection))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// A friendly label like "Asia/Tokyo (GMT+9)".
    static func displayName(for identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        let offset = zone.secondsFromGMT()
        let hours = offset / 3600
        let minutes = abs(offset / 60 % 60)
        let sign = hours >= 0 ? "+" : "-"
        let offsetLabel = minutes == 0
            ? String(format: "GMT%@%d", sign, abs(hours))
            : String(format: "GMT%@%d:%02d", sign, abs(hours), minutes)
        let name = identifier.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? identifier
        return "\(name) (\(offsetLabel))"
    }
}

/// The full searchable list of zones.
private struct TimeZoneList: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List(identifiers, id: \.self) { identifier in
            Button {
                selection = identifier
                dismiss()
            } label: {
                HStack {
                    Text(ZoneIdentifierPicker.displayName(for: identifier))
                        .foregroundStyle(.primary)
                    Spacer()
                    if identifier == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $query, prompt: "Search time zones")
        .navigationTitle("Time Zone")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// Converts between a stored UTC instant and the local wall-clock a
/// `DatePicker` works with, so an instant can be picked and displayed in a
/// chosen zone regardless of the device's zone.
enum TimeZoneConversion {
    /// Interprets the wall-clock components of `localWallClock` (produced by a
    /// picker in the device zone) as if they were in `zone`, returning the
    /// corresponding UTC instant.
    static func instant(from localWallClock: Date, in zone: TimeZone) -> Date {
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        let components = deviceCal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: localWallClock
        )
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        return zoneCal.date(from: components) ?? localWallClock
    }

    /// The inverse of `instant(from:in:)`: takes a stored UTC instant and the
    /// zone it should be shown in, returning a `Date` whose device-zone
    /// wall-clock matches the instant's local wall-clock in `zone`.
    static func localTime(from instant: Date, in zone: TimeZone) -> Date {
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        let components = zoneCal.dateComponents(
            [.year, .month, .day, .hour, .minute], from: instant
        )
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        return deviceCal.date(from: components) ?? instant
    }
}
