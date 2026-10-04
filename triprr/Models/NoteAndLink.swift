//
//  NoteAndLink.swift
//  triprr
//
//  Free-text notes and titled links. Each attaches to either a Trip or an
//  Activity (exactly one of the two relationships is set).
//

import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var trip: Trip?
    var activity: Activity?

    init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        trip: Trip? = nil,
        activity: Activity? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.trip = trip
        self.activity = activity
    }
}

@Model
final class LinkItem {
    var id: UUID = UUID()
    var title: String = ""
    var urlString: String = ""
    var createdAt: Date = Date()
    var trip: Trip?
    var activity: Activity?

    init(
        id: UUID = UUID(),
        title: String = "",
        urlString: String = "",
        createdAt: Date = Date(),
        trip: Trip? = nil,
        activity: Activity? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
        self.trip = trip
        self.activity = activity
    }
}

extension LinkItem {
    /// The normalised, tappable URL for the stored string, if one can be
    /// formed. Falls back through `LinkItem.normalisedURL(from:)` so a user who
    /// types "example.com" still gets a working `https://` link.
    var url: URL? {
        LinkItem.normalisedURL(from: urlString)
    }

    /// Builds a tappable `URL` from free-form user input.
    ///
    /// Rules (pure, so it can be unit-tested):
    /// - Trims surrounding whitespace.
    /// - Returns `nil` for empty input.
    /// - If the string already carries a scheme (e.g. `https:`, `mailto:`,
    ///   `tel:`) it is parsed as-is.
    /// - Otherwise `https://` is prepended so bare hosts like `example.com`
    ///   become `https://example.com`.
    /// - Returns `nil` when the result still isn't a parseable URL, so callers
    ///   can degrade gracefully rather than crash.
    static func normalisedURL(from rawInput: String) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = hasScheme(trimmed) ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { return nil }
        // A bare "https://" (no host) is not a usable link.
        if url.scheme != nil, url.host?.isEmpty ?? true, !isSchemeOnlyAllowed(url) {
            return nil
        }
        return url
    }

    /// Whether `string` begins with a URL scheme followed by a colon
    /// (e.g. "https:", "mailto:", "tel:"), per RFC 3986's scheme grammar.
    private static func hasScheme(_ string: String) -> Bool {
        guard let colon = string.firstIndex(of: ":") else { return false }
        let scheme = string[string.startIndex..<colon]
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    /// Schemes that legitimately carry no host (e.g. `mailto:`, `tel:`).
    private static func isSchemeOnlyAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["mailto", "tel", "sms", "facetime"].contains(scheme)
    }
}
