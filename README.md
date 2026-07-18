# CrewPick iOS

Native SwiftUI implementation of the private friend-group idea board described in `docs/AUDIT_AND_IMPLEMENTATION_PLAN.md`.

## Current milestone

The repository contains:

- A dependency-free domain/data library in `Sources/CrewPickCore`.
- A local actor-backed repository and deterministic Toronto sample data.
- SwiftUI Groups, Board, Idea Details, Add Idea, reaction, shortlist, Planned, and Completed flows in `CrewPickApp`.
- Local onboarding/sign-in, create/join group, invitation sharing, member administration, comments, activity, notification preferences, and offline/error states.
- Idea ownership controls for editing/deleting, named reaction breakdowns, and returning a Planned idea to the board.
- A native Share Extension that lets someone choose a CrewPick group before queueing a URL, with App Group handoff into the add-idea flow.
- Custom/universal deep-link routing for invitations, groups, ideas, and plans, including access checks and normalized duplicate detection.
- Local link-preview metadata with an editable fallback when metadata is unavailable.
- Real iOS notification authorization states, APNs registration callbacks, and per-group preference persistence.
- A dependency-free authenticated Supabase REST/RPC boundary plus server migrations for atomic groups, secure invitations, notification preferences, and device registration.
- Swift Testing coverage with a conditional XCTest fallback for incomplete Command Line Tools installations.
- An XcodeGen project definition with branding and bundle identifiers isolated in build settings.

No secrets or production credentials are included.

## Run the iOS app

1. Install full Xcode and select it: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. Install XcodeGen if needed: `brew install xcodegen`.
3. From this directory, run `xcodegen generate` whenever `project.yml` changes.
4. Open `CrewPick.xcodeproj`, choose an iPhone simulator, and run the CrewPick scheme.

Before signing, replace `com.example.crewpick`, `PRODUCT_DISPLAY_NAME`, and the example App Group identifier (`group.com.example.crewpick`) in both entitlement files and the core default. Enable the same App Group capability for the app and share-extension identifiers in the Apple Developer portal. Keep any local public configuration in an untracked `Secrets.xcconfig` copied from `Config/Secrets.xcconfig.example`.

To exercise importing after signing, launch CrewPick once so it can cache the user’s groups, then share a webpage from Safari, select CrewPick, choose a group, and tap Post. Opening CrewPick presents the editable import preview. The custom URL scheme can be tested with links such as `crewpick://join/TRIV-88`.

## Test the domain layer

With full Xcode selected, run:

```sh
swift test
```

The tests cover ranking, combined filtering, unvoted behavior, reaction replacement/toggle, finalist selection, URL normalization, duplicate detection, invite/deep-link routing, shared import persistence, and link-preview fallback rules.

The CrewPick Xcode scheme also includes two simulator UI tests covering group → idea → comment and group → add idea → board. Run them with an available simulator selected in Xcode, or from the command line:

```sh
xcodebuild -project CrewPick.xcodeproj -scheme CrewPick \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

If working with Command Line Tools alone, the dependency-free verification path is:

```sh
swift run CrewPickCoreCheck
```

That check exercises the same ranking, filtering, reaction, URL, invitation, and duplicate rules.

## Verified environment

The baseline was verified with Xcode 26.6, XcodeGen 2.46.0, and the iOS 26.5 Simulator runtime:

- Generic iOS Simulator build succeeded.
- All 29 Swift Testing tests passed.
- Both critical-path XCUITests passed on iPhone 17 Pro.
- The app installed and launched on an iPhone 17 Pro simulator.
- The embedded share-extension target compiled and passed Xcode’s embedded-binary validation.

## Architecture

Views depend on `AppModel`; `AppModel` depends on repository protocols; `LocalStore` supplies the current data implementation. Supabase repositories can be added behind the same protocols. Domain types do not import SwiftUI or Supabase.

See `docs/AUDIT_AND_IMPLEMENTATION_PLAN.md` for attachment findings, assumptions, milestones, and integration blockers.
