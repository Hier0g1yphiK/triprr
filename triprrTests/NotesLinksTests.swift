//
//  NotesLinksTests.swift
//  triprrTests
//
//  Covers the pure URL-normalisation helper used to render links tappable
//  (Req 6.2) and round-trips Notes and LinkItems through an in-memory
//  ModelContainer on both a Trip and an Activity to prove create / edit /
//  delete persist and attach to the right parent (Req 6.1, 6.3). These mirror
//  the save paths in NoteEditView, LinkEditView and NotesLinksSection.
//

import Testing
import Foundation
import SwiftData
@testable import triprr

struct LinkURLNormalisationTests {

    @Test func prependsHTTPSWhenSchemeMissing() throws {
        let url = try #require(LinkItem.normalisedURL(from: "example.com"))
        #expect(url.scheme == "https")
        #expect(url.host == "example.com")
    }

    @Test func preservesExistingHTTPScheme() throws {
        let url = try #require(LinkItem.normalisedURL(from: "http://example.com/path"))
        #expect(url.scheme == "http")
        #expect(url.absoluteString == "http://example.com/path")
    }

    @Test func preservesExistingHTTPSScheme() throws {
        let url = try #require(LinkItem.normalisedURL(from: "https://www.tokyometro.jp/en/"))
        #expect(url.scheme == "https")
    }

    @Test func trimsSurroundingWhitespace() throws {
        let url = try #require(LinkItem.normalisedURL(from: "  example.com  "))
        #expect(url.absoluteString == "https://example.com")
    }

    @Test func allowsHostlessSchemes() throws {
        let mail = try #require(LinkItem.normalisedURL(from: "mailto:hi@example.com"))
        #expect(mail.scheme == "mailto")
        let tel = try #require(LinkItem.normalisedURL(from: "tel:+15551234567"))
        #expect(tel.scheme == "tel")
    }

    @Test func rejectsEmptyInput() {
        #expect(LinkItem.normalisedURL(from: "") == nil)
        #expect(LinkItem.normalisedURL(from: "   ") == nil)
    }

    @Test func rejectsSchemeOnlyWithoutHost() {
        #expect(LinkItem.normalisedURL(from: "https://") == nil)
    }

    @Test func linkItemURLUsesNormalisation() throws {
        let link = LinkItem(title: "Bare", urlString: "example.org")
        let url = try #require(link.url)
        #expect(url.scheme == "https")
        #expect(url.host == "example.org")
    }
}

@MainActor
struct NotesLinksPersistenceTests {

    private let container = SampleData.emptyContainer()

    private func makeContext() -> ModelContext {
        container.mainContext
    }

    private func makeTrip(in context: ModelContext) -> Trip {
        let trip = Trip(
            name: "Notes Trip",
            startDate: Date(),
            endDate: Date().addingTimeInterval(5 * 86_400)
        )
        context.insert(trip)
        try? context.save()
        return trip
    }

    private func makeActivity(in context: ModelContext, trip: Trip) -> Activity {
        let activity = Activity(title: "Visit", startDate: Date(), trip: trip)
        context.insert(activity)
        try? context.save()
        return activity
    }

    // MARK: - Trip notes & links

    @Test func tripNoteCreateEditDeleteRoundTrips() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)

        // CREATE — mirrors NoteEditView.save() via owner.makeNote.
        let owner = NotesLinksOwner.trip(trip)
        let note = owner.makeNote(text: "Pack adapters")
        context.insert(note)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.trip?.id == trip.id)
        #expect(fetched.first?.activity == nil)

        // EDIT.
        let toEdit = try #require(fetched.first)
        toEdit.text = "Pack adapters and SIM"
        try context.save()
        fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.first?.text == "Pack adapters and SIM")

        // DELETE.
        context.delete(toEdit)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
    }

    @Test func tripLinkCreateEditDeleteRoundTrips() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)
        let owner = NotesLinksOwner.trip(trip)

        let link = owner.makeLink(title: "Metro", urlString: "tokyometro.jp")
        context.insert(link)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<LinkItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.trip?.id == trip.id)
        #expect(fetched.first?.activity == nil)
        // The stored string stays raw; the tappable URL is normalised.
        #expect(fetched.first?.urlString == "tokyometro.jp")
        #expect(fetched.first?.url?.scheme == "https")

        let toEdit = try #require(fetched.first)
        toEdit.title = "Tokyo Metro"
        toEdit.urlString = "https://www.tokyometro.jp/en/"
        try context.save()
        fetched = try context.fetch(FetchDescriptor<LinkItem>())
        #expect(fetched.first?.title == "Tokyo Metro")
        #expect(fetched.first?.url?.absoluteString == "https://www.tokyometro.jp/en/")

        context.delete(toEdit)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<LinkItem>()).isEmpty)
    }

    // MARK: - Activity notes & links

    @Test func activityNoteAndLinkAttachToActivity() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)
        let activity = makeActivity(in: context, trip: trip)
        let owner = NotesLinksOwner.activity(activity)

        let note = owner.makeNote(text: "Buy tickets online")
        let link = owner.makeLink(title: "Booking", urlString: "example.com/book")
        context.insert(note)
        context.insert(link)
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.activity?.id == activity.id)
        #expect(notes.first?.trip == nil)

        let links = try context.fetch(FetchDescriptor<LinkItem>())
        #expect(links.count == 1)
        #expect(links.first?.activity?.id == activity.id)
        #expect(links.first?.trip == nil)
    }

    // MARK: - Cascade (not re-implemented, just verified intact)

    @Test func deletingTripCascadesToNotesAndLinks() throws {
        let context = makeContext()
        let trip = makeTrip(in: context)
        let owner = NotesLinksOwner.trip(trip)
        context.insert(owner.makeNote(text: "A note"))
        context.insert(owner.makeLink(title: "A link", urlString: "example.com"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Note>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<LinkItem>()).count == 1)

        context.delete(trip)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Note>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LinkItem>()).isEmpty)
    }
}
