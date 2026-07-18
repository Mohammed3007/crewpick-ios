import SwiftUI

struct IdeaDetailView: View {
    @EnvironmentObject private var model: AppModel
    let ideaID: UUID
    let group: FriendGroup
    @State private var commentText = ""
    @FocusState private var commentFocused: Bool
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var idea: Idea? { model.ideasByGroup[group.id]?.first(where: { $0.id == ideaID }) }

    var body: some View {
        Group {
            if let idea {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LinearGradient(colors: [.orange, .pink.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 240).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 12) {
                            if idea.status != .board {
                                Label(idea.status == .planned ? "Planned" : "Completed", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.bold()).foregroundStyle(CrewPickTheme.success)
                            }
                            Text(idea.title).font(.largeTitle.bold())
                                .accessibilityIdentifier("idea-detail-title")
                            Text([idea.location, idea.priceLevel.map { String(repeating: "$", count: $0) }, idea.category.rawValue].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            if let note = idea.note { Text(note).font(.body) }
                            if let sourceURL = idea.sourceURL { Link("Open original link", destination: sourceURL).buttonStyle(.bordered) }
                            ReactionControl(idea: idea, userID: model.currentUser.id) { kind in
                                Task { await model.react(kind, to: idea.id, in: group.id) }
                            }
                            reactionBreakdown(idea)
                            if idea.status == .planned {
                                Button("Return to board", systemImage: "arrow.uturn.backward") {
                                    Task { await model.returnToBoard(idea, in: group.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                            Divider()
                            Text("Comments").font(.headline)
                            if idea.comments.isEmpty { Text("No comments yet.").foregroundStyle(.secondary) }
                            ForEach(idea.comments) { comment in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(comment.author.displayName.prefix(1)).font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 30, height: 30).background(CrewPickTheme.accent, in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(comment.author.displayName).font(.subheadline.bold())
                                        Text(comment.body)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 10) {
                        TextField("Add a comment", text: $commentText, axis: .vertical)
                            .lineLimit(1...4).focused($commentFocused)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                            .accessibilityIdentifier("comment-field")
                        Button("Post", systemImage: "arrow.up.circle.fill") {
                            let body = commentText
                            commentText = ""; commentFocused = false
                            Task { await model.addComment(body, to: idea.id, in: group.id) }
                        }
                        .labelStyle(.iconOnly).font(.title2)
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Post comment")
                        .accessibilityIdentifier("post-comment")
                    }
                    .padding(.horizontal).padding(.vertical, 8).background(.ultraThinMaterial)
                }
            } else {
                ContentUnavailableView("Idea unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let idea, canManage(idea) {
                Menu("Idea actions", systemImage: "ellipsis.circle") {
                    Button("Edit idea", systemImage: "pencil") { showingEdit = true }
                    Button("Delete idea", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let idea { AddIdeaView(group: group, idea: idea) }
        }
        .confirmationDialog("Delete this idea?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete idea", role: .destructive) {
                guard let idea else { return }
                Task { if await model.delete(idea, in: group.id) { dismiss() } }
            }
        } message: {
            Text("This removes the idea, its reactions, and comments for everyone in the group.")
        }
    }

    private func canManage(_ idea: Idea) -> Bool {
        idea.creator.id == model.currentUser.id || group.members.contains { $0.user.id == model.currentUser.id && $0.role == .admin }
    }

    @ViewBuilder private func reactionBreakdown(_ idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ReactionKind.allCases) { kind in
                let names = idea.reactions.filter { $0.kind == kind }.compactMap { reaction in
                    group.members.first(where: { $0.user.id == reaction.userID })?.user.displayName
                }
                if !names.isEmpty {
                    Text("\(kind.rawValue): \(names.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reaction breakdown")
    }
}

struct AddIdeaView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let group: FriendGroup
    @State private var draft = IdeaDraft()
    @State private var urlText = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isImporting = false
    @State private var duplicateIdeaID: UUID?
    private let onSaved: () -> Void
    private let onOpenDuplicate: (UUID) -> Void
    private let existingIdeaID: UUID?

    init(group: FriendGroup, idea: Idea? = nil, initialURL: URL? = nil, onSaved: @escaping () -> Void = {}, onOpenDuplicate: @escaping (UUID) -> Void = { _ in }) {
        self.group = group
        self.onSaved = onSaved
        self.onOpenDuplicate = onOpenDuplicate
        self.existingIdeaID = idea?.id
        _draft = State(initialValue: idea.map(IdeaDraft.init) ?? IdeaDraft())
        _urlText = State(initialValue: initialURL?.absoluteString ?? idea?.sourceURL?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Link (optional)") {
                    TextField("https://…", text: $urlText).textInputAutocapitalization(.never).keyboardType(.URL)
                    Button(isImporting ? "Loading preview…" : "Load link preview", systemImage: "link.badge.plus") {
                        Task { await loadPreview() }
                    }
                    .disabled(URL(string: urlText)?.host == nil || isImporting)
                    Text("If a preview can't be loaded, the URL is kept and you can fill in the details.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Idea") {
                    TextField("Title", text: $draft.title)
                        .accessibilityIdentifier("idea-title-field")
                    Picker("Category", selection: $draft.category) { ForEach(IdeaCategory.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Location", text: $draft.location)
                    Picker("Price", selection: $draft.priceLevel) {
                        Text("Not set").tag(Int?.none)
                        ForEach(1...3, id: \.self) { Text(String(repeating: "$", count: $0)).tag(Int?.some($0)) }
                    }
                    TextField("Note", text: $draft.note, axis: .vertical).lineLimit(3...6)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                        if let duplicateIdeaID {
                            Button("Open existing idea") { dismiss(); onOpenDuplicate(duplicateIdeaID) }
                        }
                    }
                }
            }
            .navigationTitle(existingIdeaID == nil ? "New idea" : "Edit idea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingIdeaID == nil ? "Post" : "Save") { Task { await save() } }.disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        draft.sourceURL = urlText.isEmpty ? nil : URL(string: urlText)
        do {
            if let existingIdeaID { try await model.update(draft, ideaID: existingIdeaID, in: group.id) }
            else { try await model.add(draft, to: group.id) }
            onSaved()
            dismiss()
        } catch RepositoryError.duplicateIdea(let existingID) {
            duplicateIdeaID = existingID
            errorMessage = "This link is already on the board. Open the existing idea instead."
        } catch {
            errorMessage = "The idea couldn't be saved. Try again."
        }
    }

    private func loadPreview() async {
        guard let url = URL(string: urlText), url.host != nil else { return }
        isImporting = true; defer { isImporting = false }
        do {
            draft = try await model.importPreview(for: url)
            errorMessage = nil
        } catch {
            draft.sourceURL = url
            errorMessage = "We couldn't read that site's preview. Add a title and the link can still be saved."
        }
    }
}

private extension IdeaDraft {
    init(idea: Idea) {
        self.init(
            title: idea.title,
            category: idea.category,
            location: idea.location ?? "",
            priceLevel: idea.priceLevel,
            note: idea.note ?? "",
            sourceURL: idea.sourceURL
        )
    }
}
