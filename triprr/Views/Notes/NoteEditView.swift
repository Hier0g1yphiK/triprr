//
//  NoteEditView.swift
//  triprr
//
//  Create or edit a free-text Note on a Trip or an Activity (Req 6.1, 6.3).
//  Follows the editor Mode pattern used by StayEditView / ActivityEditView:
//  `.create(owner)` attaches a new Note to the correct parent; `.edit(note)`
//  mutates an existing one. Saving persists via the ModelContext and dismisses;
//  an empty note can't be saved.
//

import SwiftUI
import SwiftData

struct NoteEditView: View {
    enum Mode {
        case create(NotesLinksOwner)
        case edit(Note)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var text: String = ""
    @State private var didLoad = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Write a note", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle(isEditing ? "Edit Note" : "New Note")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if case .edit(let note) = mode {
            text = note.text
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create(let owner):
            let note = owner.makeNote(text: trimmed)
            modelContext.insert(note)
        case .edit(let note):
            note.text = trimmed
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview("Create") {
    NoteEditView(mode: .create(.trip(SampleData.makeTokyoTrip())))
        .modelContainer(SampleData.container)
}

#Preview("Edit — Light") {
    NoteEditView(mode: .edit(SampleData.makeTokyoTrip().notes[0]))
        .modelContainer(SampleData.container)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    NoteEditView(mode: .edit(SampleData.makeTokyoTrip().notes[0]))
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
