import SwiftUI
import UIKit

struct GroupMembersView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var memberToRemove: GroupMember?
    @State private var copied = false

    private var group: FriendGroup? { model.group(id: groupID) }
    private var isAdmin: Bool { group?.members.contains(where: { $0.user.id == model.currentUser.id && $0.role == .admin }) == true }
    private var inviteCode: String { "CREW-\(groupID.uuidString.prefix(4))" }
    private var inviteURL: URL { URL(string: "https://crewpick.app/join/\(inviteCode)")! }

    var body: some View {
        NavigationStack {
            List {
                if let group {
                    Section {
                        ShareLink(item: inviteURL, subject: Text("Join \(group.name) on CrewPick"), message: Text("Use invite code \(inviteCode)")) {
                            Label("Share invitation", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = inviteCode
                            copied = true
                        } label: {
                            LabeledContent(copied ? "Copied" : "Copy invite code", value: inviteCode)
                        }
                    } header: {
                        Text("Invite friends")
                    } footer: {
                        Text("Invitations will expire after seven days when the Supabase backend is enabled.")
                    }

                    Section("\(group.members.count) members") {
                        ForEach(group.members) { member in
                            HStack(spacing: 12) {
                                Text(member.user.displayName.prefix(1)).font(.headline).foregroundStyle(.white)
                                    .frame(width: 38, height: 38).background(CrewPickTheme.accent, in: Circle())
                                VStack(alignment: .leading) {
                                    Text(member.user.displayName + (member.user.id == model.currentUser.id ? " (you)" : ""))
                                    Text(member.role == .admin ? "Admin" : "Member").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isAdmin && member.user.id != model.currentUser.id {
                                    Button("Remove", role: .destructive) { memberToRemove = member }.font(.subheadline)
                                }
                            }
                        }
                    }

                    Section("Notifications") {
                        Picker("New ideas", selection: Binding(
                            get: { model.notificationPreferences[groupID] ?? .instant },
                            set: { model.setNotificationPreference($0, for: groupID) }
                        )) {
                            ForEach(NotificationFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                } else {
                    ContentUnavailableView("Group unavailable", systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle(group?.name ?? "Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Remove member?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), presenting: memberToRemove) { member in
                Button("Remove \(member.user.displayName)", role: .destructive) {
                    Task { await model.removeMember(member.user.id, from: groupID) }
                }
                Button("Cancel", role: .cancel) { memberToRemove = nil }
            } message: { member in Text("They will lose access to this private group and its ideas.") }
        }
    }
}
