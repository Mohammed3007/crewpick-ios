# CrewPick v1 release readiness

## Verified locally

- Native SwiftUI onboarding, groups, boards, reactions, named reaction breakdowns, comments, decision mode, planning/completion, activity, profile, and error/offline states.
- Manual and URL idea entry, editable preview fallback, normalized duplicate handling, edit/delete ownership checks, and return-to-board behavior.
- Share Extension target with destination-group selection and durable App Group handoff.
- Group/invitation/idea/plan deep-link parsing and private-group access checks.
- iOS notification authorization states, APNs registration callbacks, and per-group preference persistence boundary.
- Supabase schema, RLS policies, atomic social/plan functions, expiring invitation RPCs, trusted activity triggers, device/preference RPCs, and official Swift SDK repositories.
- Native Sign in with Apple, email magic-link callback handling, session restoration/sign-out, and automatic production/local-preview composition based on configuration.
- 30 Swift Testing tests and three XCUITests, including dark mode at an accessibility text size, pass with Xcode 26.6 and iOS 26.5 Simulator.

## Required before a private TestFlight beta

These steps need project/account values and cannot be completed with example identifiers:

1. Choose the permanent app identifier, Share Extension identifier, App Group identifier, and display name.
2. Select the Apple Developer team in Xcode and enable App Groups, Sign in with Apple, Push Notifications, and Associated Domains for the real identifiers.
3. Create a Supabase project, copy only its project URL and publishable/anonymous key into untracked `Config/Secrets.xcconfig`, and apply all migrations in filename order.
4. Configure Apple as a Supabase Auth provider and add `crewpick://auth-callback` plus the eventual universal-link callback to Supabase's allowed redirect URLs.
5. Run RLS integration tests with at least two accounts in different groups. Confirm guessed group/idea UUIDs and another user's reaction mutations are rejected.
6. Deploy metadata-fetch and APNs-dispatch Edge Functions. Keep APNs signing material in server secrets, never in the app or repository.
7. Host `apple-app-site-association` for the final domain and add the final Associated Domains entitlement.
8. Exercise Apple sign-in, email magic link, Share Sheet, universal links, notification receipt, and notification deep links on a physical iPhone.
9. Add final App Store icon/artwork, privacy policy/support URLs, privacy nutrition details, screenshots, and release signing.

## Intentional v1 behavior

- New-idea notifications exclude the contributor; reaction notifications are not sent.
- Unknown link metadata remains an editable draft instead of blocking the save.
- One active Planned idea is allowed per group.
- Local category gradients are semantic placeholders until approved remote imagery is available.
- No reservations, calendar integration, payments, public discovery, AI recommendations, or web/Android client are in v1.
