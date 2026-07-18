import SwiftUI

struct MemberAvatarStack: View {
    let members: [GroupMember]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(members.prefix(4)) { member in
                Text(member.user.displayName.prefix(1))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(avatarColor(member.user.id), in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .accessibilityLabel(member.user.displayName)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group members")
    }

    private func avatarColor(_ id: UUID) -> Color {
        let colors: [Color] = [.orange, .purple, .green, .blue, .pink]
        return colors[abs(id.hashValue) % colors.count]
    }
}

struct ReactionControl: View {
    let idea: Idea
    let userID: UUID
    let onSelect: (ReactionKind) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ReactionKind.allCases) { kind in
                Button {
                    onSelect(kind)
                } label: {
                    VStack(spacing: 2) {
                        Text(kind.rawValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(idea.count(kind), format: .number)
                            .font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(foreground(kind))
                    .background(background(kind), in: Capsule())
                    .overlay(Capsule().stroke(.separator.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.rawValue), \(idea.count(kind)) reactions")
                .accessibilityValue(idea.reaction(from: userID) == kind ? "Selected" : "Not selected")
            }
        }
    }

    private func background(_ kind: ReactionKind) -> Color {
        guard idea.reaction(from: userID) == kind else { return Color.secondary.opacity(0.08) }
        return switch kind {
        case .inForIt: CrewPickTheme.success.opacity(0.16)
        case .maybe: CrewPickTheme.warning.opacity(0.18)
        case .pass: Color.secondary.opacity(0.18)
        }
    }

    private func foreground(_ kind: ReactionKind) -> Color {
        guard idea.reaction(from: userID) == kind else { return .secondary }
        return switch kind {
        case .inForIt: CrewPickTheme.success
        case .maybe: CrewPickTheme.warning
        case .pass: .primary
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color(.systemBackground) : .secondary)
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .background(selected ? Color.primary : Color(.secondarySystemBackground), in: Capsule())
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
