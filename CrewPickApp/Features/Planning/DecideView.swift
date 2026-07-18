import SwiftUI

struct DecideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let group: FriendGroup
    @State private var category: IdeaCategory?
    @State private var maximumPrice: Int?
    @State private var maximumDistance: Double?
    @State private var finalists: [Idea] = []
    @State private var selected: Idea?
    @State private var hasRun = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !hasRun { preferences } else { shortlist }
                }
                .padding()
            }
            .navigationTitle(hasRun ? "Top three" : "Decide for us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .confirmationDialog("Mark as Planned?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { idea in
                Button("Mark \(idea.title) as Planned") {
                    Task { await model.markPlanned(idea, in: group.id); dismiss() }
                }
                Button("Cancel", role: .cancel) { selected = nil }
            } message: { idea in Text("It will appear as the active plan on \(group.name).") }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keep it quick. Choose what matters, or skip the filters.").foregroundStyle(.secondary)
            preferenceSection("Category") {
                FilterChip(title: "Any", selected: category == nil) { category = nil }
                ForEach(IdeaCategory.allCases) { value in FilterChip(title: value.rawValue, selected: category == value) { category = value } }
            }
            preferenceSection("Maximum price") {
                FilterChip(title: "Any", selected: maximumPrice == nil) { maximumPrice = nil }
                ForEach(1...3, id: \.self) { value in FilterChip(title: String(repeating: "$", count: value), selected: maximumPrice == value) { maximumPrice = value } }
            }
            preferenceSection("Maximum distance") {
                FilterChip(title: "Anywhere", selected: maximumDistance == nil) { maximumDistance = nil }
                ForEach([2.0, 5.0, 10.0], id: \.self) { value in FilterChip(title: "≤ \(Int(value)) km", selected: maximumDistance == value) { maximumDistance = value } }
            }
            Button("Show us three", systemImage: "sparkles") { run() }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            Button("Skip filters") { category = nil; maximumPrice = nil; maximumDistance = nil; run() }
                .frame(maxWidth: .infinity)
        }
    }

    private var shortlist: some View {
        VStack(alignment: .leading, spacing: 14) {
            if finalists.isEmpty {
                ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Go back and loosen a filter."))
            } else {
                ForEach(Array(finalists.enumerated()), id: \.element.id) { index, idea in
                    Button { selected = idea } label: {
                        HStack(spacing: 14) {
                            Text("\(index + 1)").font(.title2.bold()).foregroundStyle(CrewPickTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title).font(.headline).foregroundStyle(.primary)
                                Text(explanation(idea)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding().warmCard()
                    }
                    .buttonStyle(.plain)
                }
                Button("Pick for us", systemImage: "dice.fill") {
                    selected = BoardEngine.pickForUs(from: finalists) { Int.random(in: 0..<$0) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
        }
    }

    private func preferenceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8, content: content) }
        }
    }

    private func run() {
        finalists = BoardEngine.finalists(from: model.ideasByGroup[group.id] ?? [], filter: .init(category: category, maximumPrice: maximumPrice, maximumDistanceKilometres: maximumDistance))
        hasRun = true
    }

    private func explanation(_ idea: Idea) -> String {
        let memberCount = group.members.count
        if idea.count(.inForIt) > 0 { return "\(idea.count(.inForIt)) of \(memberCount) friends are in" }
        if idea.count(.maybe) > 0 { return "\(idea.count(.maybe)) maybes — could tip fast" }
        return "Fresh pick — no votes yet"
    }
}
