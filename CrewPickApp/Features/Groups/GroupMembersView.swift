import SwiftUI
import UIKit

struct GroupMembersView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var memberToRemove: GroupMember?
    @State private var copied = false
    @State private var invitation: GroupInvitation?
    @State private var isCreatingInvitation = false
    @State private var invitationError: String?

    private var group: FriendGroup? { model.group(id: groupID) }
    private var isAdmin: Bool { group?.members.contains(where: { $0.user.id == model.currentUser.id && $0.role == .admin }) == true }
    var body: some View {
        NavigationStack {
            List {
                if let group {
                    Section {
                        if let invitation, let inviteURL = invitation.url {
                            ShareLink(item: inviteURL, subject: Text("Join \(group.name) on CrewPick"), message: Text("Use invite code \(invitation.code)")) {
                                Label("Share invitation", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                UIPasteboard.general.string = invitation.code
                                copied = true
                            } label: {
                                LabeledContent(copied ? "Copied" : "Copy invite code", value: invitation.code)
                            }
                            LabeledContent("Expires", value: invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if isAdmin {
                            Button {
                                Task { await createInvitation() }
                            } label: {
                                if isCreatingInvitation { ProgressView() }
                                else { Label("Create 7-day invitation", systemImage: "person.badge.plus") }
                            }
                            .disabled(isCreatingInvitation)
                        } else {
                            Text("Ask a group admin to create an invitation.")
                                .foregroundStyle(.secondary)
                        }
                        if let invitationError {
                            Text(invitationError).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Invite friends")
                    } footer: {
                        Text("For privacy, invitation codes expire after seven days.")
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

    private func createInvitation() async {
        isCreatingInvitation = true
        invitationError = nil
        defer { isCreatingInvitation = false }
        do {
            invitation = try await model.createInvitation(for: groupID)
        } catch {
            invitationError = "CrewPick couldn't create an invitation. Try again."
        }
    }
}
