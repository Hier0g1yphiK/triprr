//
//  NotesLinksSection.swift
//  triprr
//
//  A reusable Form section that lets the user attach, edit and delete free-text
//  Notes and titled Links on either a Trip or an Activity (Req 6.1, 6.2, 6.3).
//
//  Note and LinkItem each belong to exactly one of a Trip or an Activity, so the
//  owner is abstracted behind `NotesLinksOwner`: it exposes the current notes
//  and links and knows how to attach a freshly created one to the correct
//  parent relationship. This keeps a single UI usable from the trip dashboard
//  and the activity editor without duplication.
//
//  Links render as tappable: a valid, normalised URL opens via SwiftUI `Link`
//  showing the title as its label; an un-parseable URL degrades to plain,
//  non-tappable text so the view never crashes (Req 6.2).
//

import SwiftUI
import SwiftData

/// Identifies which entity a notes/links section is editing and knows how to
/// attach a new Note or LinkItem to it. Both owners share one editor UI.
enum NotesLinksOwner {
    case trip(Trip)
    case activity(Activity)

    /// The owner's notes, newest first.
    var notes: [Note] {
        switch self {
        case .trip(let trip): return trip.notes.sorted { $0.createdAt < $1.createdAt }
        case .activity(let activity): return activity.activityNotes.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// The owner's links, oldest first (stable add order).
    var links: [LinkItem] {
        switch self {
        case .trip(let trip): return trip.links.sorted { $0.createdAt < $1.createdAt }
        case .activity(let activity): return activity.links.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Creates a Note already wired to the correct parent relationship.
    func makeNote(text: String) -> Note {
        switch self {
        case .trip(let trip): return Note(text: text, trip: trip)
        case .activity(let activity): return Note(text: text, activity: activity)
        }
    }

    /// Creates a LinkItem already wired to the correct parent relationship.
    func makeLink(title: String, urlString: String) -> LinkItem {
        switch self {
        case .trip(let trip): return LinkItem(title: title, urlString: urlString, trip: trip)
        case .activity(let activity): return LinkItem(title: title, urlString: urlString, activity: activity)
        }
    }
}

/// Two Form sections — Notes and Links — with add/edit/delete, usable for any
/// `NotesLinksOwner`. Drop into any `Form`.
struct NotesLinksSection: View {
    let owner: NotesLinksOwner

    @Environment(\.modelContext) private var modelContext

    @State private var editingNote: Note?
    @State private var isAddingNote = false
    @State private var editingLink: LinkItem?
    @State private var isAddingLink = false

    var body: some View {
        notesSection
        linksSection
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section {
            if owner.notes.isEmpty {
                Text("No notes yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(owner.notes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        Text(note.text)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Notes")
                Spacer()
                Button {
                    isAddingNote = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(isPresented: $isAddingNote) {
            NoteEditView(mode: .create(owner))
        }
        .sheet(item: $editingNote) { note in
            NoteEditView(mode: .edit(note))
        }
    }

    // MARK: - Links

    private var linksSection: some View {
        Section {
            if owner.links.isEmpty {
                Text("No links yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(owner.links) { link in
                    LinkRow(link: link) {
                        editingLink = link
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(link)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Links")
                Spacer()
                Button {
                    isAddingLink = true
                } label: {
                    Label("Add Link", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(isPresented: $isAddingLink) {
            LinkEditView(mode: .create(owner))
        }
        .sheet(item: $editingLink) { link in
            LinkEditView(mode: .edit(link))
        }
    }

    // MARK: - Delete

    private func delete(_ note: Note) {
        modelContext.delete(note)
        try? modelContext.save()
    }

    private func delete(_ link: LinkItem) {
        modelContext.delete(link)
        try? modelContext.save()
    }
}

/// A single link row: the title opens the normalised URL when tappable, with an
/// "edit" affordance; an invalid URL degrades to plain text (Req 6.2).
private struct LinkRow: View {
    let link: LinkItem
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let url = link.url {
                Link(destination: url) {
                    label(tappable: true)
                }
            } else {
                label(tappable: false)
            }
            Spacer(minLength: 8)
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit link")
        }
    }

    @ViewBuilder
    private func label(tappable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .foregroundStyle(tappable ? Color.accentColor : .primary)
            Text(link.urlString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        let trimmed = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? link.urlString : trimmed
    }
}
