//
//  LinkEditView.swift
//  triprr
//
//  Create or edit a titled Link on a Trip or an Activity (Req 6.1, 6.2, 6.3).
//  Stores a title alongside the URL. The URL is kept as the user typed it, and
//  rendered tappable elsewhere via `LinkItem.normalisedURL(from:)`, which
//  prepends `https://` when a scheme is missing. A live preview row shows
//  whether the entered URL resolves to something openable so the user gets
//  feedback before saving. Saving requires a URL that normalises to a valid
//  link; the title is optional and falls back to the URL when shown.
//

import SwiftUI
import SwiftData

struct LinkEditView: View {
    enum Mode {
        case create(NotesLinksOwner)
        case edit(LinkItem)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title: String = ""
    @State private var urlString: String = ""
    @State private var didLoad = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// The URL the entered string normalises to, if any.
    private var normalisedURL: URL? {
        LinkItem.normalisedURL(from: urlString)
    }

    private var canSave: Bool { normalisedURL != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("Title", text: $title)
#if os(iOS)
                        .textInputAutocapitalization(.words)
#endif
                    TextField("URL", text: $urlString)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                        .autocorrectionDisabled()
                }

                Section("Preview") {
                    if let url = normalisedURL {
                        Link(destination: url) {
                            Label(previewTitle, systemImage: "link")
                        }
                        Text(url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Label(
                            urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Enter a URL to open."
                                : "That doesn't look like a valid URL.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Link" : "New Link")
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

    private var previewTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? urlString.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if case .edit(let link) = mode {
            title = link.title
            urlString = link.urlString
        }
    }

    private func save() {
        guard canSave else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create(let owner):
            let link = owner.makeLink(title: trimmedTitle, urlString: trimmedURL)
            modelContext.insert(link)
        case .edit(let link):
            link.title = trimmedTitle
            link.urlString = trimmedURL
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview("Create") {
    LinkEditView(mode: .create(.trip(SampleData.makeTokyoTrip())))
        .modelContainer(SampleData.container)
}

#Preview("Edit — Light") {
    LinkEditView(mode: .edit(SampleData.makeTokyoTrip().links[0]))
        .modelContainer(SampleData.container)
        .preferredColorScheme(.light)
}

#Preview("Edit — Dark") {
    LinkEditView(mode: .edit(SampleData.makeTokyoTrip().links[0]))
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
