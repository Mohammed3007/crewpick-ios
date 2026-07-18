# CrewPick attachment audit and implementation plan

## Audit summary

The approved product brief describes a private board for friend groups of 3–12 people. The validated loop is group membership → save an idea → react → rank/filter → shortlist → plan → complete. Comments are treated as MVP scope because they appear in both the Idea Details requirements and the initial entity list.

The attached prototype contains 14 primary simulated screens: welcome, sign in, groups, create/join, board, idea details, add/edit/import, import failure, decision preferences, shortlist, plan detail, members/invite, activity, and profile. It also demonstrates loading, empty, duplicate, offline, notification-primer, and notification-denied states with seven realistic Toronto ideas.

The prototype is useful visual direction, but not production implementation guidance in these areas:

- It uses custom web positioning instead of native navigation, tab, sheet, keyboard, focus, and safe-area behavior.
- A whole idea card is clickable while nested reaction buttons are also clickable. Native SwiftUI uses separate accessible controls and explicit navigation targets.
- Destructive member removal and idea deletion have no confirmation or role-aware failure state.
- Notification permission is simulated and not tied to `UNUserNotificationCenter` authorization state.
- Link import assumes known demo results; real imports need normalized URL duplicate checks, editable fallback data, cancellation, retry, and offline preservation.
- “Pick for us” chooses from every finalist. The brief says similarly ranked finalists, so the domain rule limits randomness to finalists within one “I'm in” and one “Maybe” of the leader.
- The web sort promotes “Just added” ahead of ranking. The approved ranking rule does not, so native ranking is strictly “I'm in,” Maybe, then recency.
- The prototype only exposes Food, Activity, and Event board chips. Trip and Other remain supported through the full filter model and add form.
- Colour-only reaction states need labels, selected values, and VoiceOver announcements.
- The prototype's gradient placeholders are not content images. The local slice keeps category gradients intentionally; production should load remote images with a semantic fallback.
- Admin capabilities, invitation expiry/revocation, concurrent updates, deep-link restoration, and permission-denied backend states are not modeled.

## Environment and repository

- Working repository: `/Users/mohammed/Documents/Plans`; it was an empty Git repository with no commits.
- Attachments: `/Users/mohammed/PlansApp`; no repository or native source existed there.
- Installed compiler: Apple Swift 6.3.3.
- Verified toolchain: Xcode 26.6, XcodeGen 2.46.0, and iOS 26.5 Simulator runtime.
- The generated app and Share Extension build for the iOS Simulator, all 29 Swift Testing tests and three XCUITests pass, and the app launches on an iPhone 17 Pro simulator.
- `project.yml` remains the deterministic project definition; regenerate `CrewPick.xcodeproj` after changing it.

## Milestones

1. **Foundation and local board slice — complete.** Feature folders, domain/data boundaries, design tokens, deterministic samples, Groups tab, board, filters, details, reactions, add idea, decision filters, shortlist, planning/completion, and core tests.
2. **Complete local product loop — complete.** Preview onboarding/auth, create/join/invite/member administration, imported-link confirmation/failure/duplicate recovery, comments, activity, notification settings, loading/offline/error/permission states, ownership controls, and UI tests.
3. **Supabase foundation — partial.** Migrations, RLS, transactional RPCs, client transport, and setup documentation are present; real-project policy tests, remote repositories, realtime, storage, and seeds still require a configured project.
4. **Authentication and invitations — account configuration required.** Secure invitation RPCs and deep-link parsing exist; native Apple/email auth activation and session restoration require the real Apple/Supabase identifiers.
5. **Share extension and deferred imports — implementation complete.** App Group queue, extension-safe URL intake and group choice, containing-app reconciliation, metadata abstraction, and failure recovery build and are tested at the shared-store boundary.
6. **Notifications and deep links — partial.** APNs registration, authorization states, Instant/Digest/Off persistence, RPC interface, routing, and local tests exist; APNs dispatch and universal-link hosting require external configuration.
7. **Quality and beta polish — partial.** Critical-path UI tests and dark/accessibility-size coverage pass; physical-device capability testing, final branding, privacy metadata, and release signing remain.

## Assumptions that do not block work

- CrewPick is the working display name. Bundle IDs and display name remain build settings.
- iOS 17 is the minimum deployment target; this can change before beta.
- A group may have one active plan in the MVP, matching the prototype.
- Selecting an existing reaction toggles it off; selecting another replaces it.
- Unknown distance/price does not satisfy a maximum-distance/price filter.
- URL duplicates are scoped to one group and compare normalized URLs.
- Imported metadata is untrusted draft data and always editable before posting.
- Local gradients are placeholders until approved image assets or remote storage exist.

## Decisions that genuinely block later milestones

None block local implementation. Supabase project configuration, Apple team/capabilities, final bundle ID/App Group ID, associated-domain host, APNs credentials, and final branding are required only when their respective integrations begin.
