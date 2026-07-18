# CrewPick iOS

Native SwiftUI implementation of the private friend-group idea board described in `docs/AUDIT_AND_IMPLEMENTATION_PLAN.md`.

## Current milestone

The repository contains:

- A dependency-free domain/data library in `Sources/CrewPickCore`.
- A local actor-backed repository and deterministic Toronto sample data.
- SwiftUI Groups, Board, Idea Details, Add Idea, reaction, shortlist, Planned, and Completed flows in `CrewPickApp`.
- Swift Testing coverage with a conditional XCTest fallback for incomplete Command Line Tools installations.
- An XcodeGen project definition with branding and bundle identifiers isolated in build settings.

No secrets or production credentials are included.

## Run the iOS app

1. Install full Xcode and select it: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
2. Install XcodeGen if needed: `brew install xcodegen`.
3. From this directory, run `xcodegen generate` whenever `project.yml` changes.
4. Open `CrewPick.xcodeproj`, choose an iPhone simulator, and run the CrewPick scheme.

Before signing, replace `com.example.crewpick`, `PRODUCT_DISPLAY_NAME`, and the example App Group identifier. Keep any local public configuration in an untracked `Secrets.xcconfig` copied from `Config/Secrets.xcconfig.example`.

## Test the domain layer

With full Xcode selected, run:

```sh
swift test
```

The tests cover ranking, combined filtering, unvoted behavior, reaction replacement/toggle, finalist selection, URL normalization, duplicate detection, and invite-code rules.

If working with Command Line Tools alone, the dependency-free verification path is:

```sh
swift run CrewPickCoreCheck
```

That check exercises the same ranking, filtering, reaction, URL, invitation, and duplicate rules.

## Verified environment

The baseline was verified with Xcode 26.6, XcodeGen 2.46.0, and the iOS 26.5 Simulator runtime:

- Generic iOS Simulator build succeeded.
- All 10 Swift Testing tests passed.
- The app installed and launched on an iPhone 17 Pro simulator.

## Architecture

Views depend on `AppModel`; `AppModel` depends on repository protocols; `LocalStore` supplies the current data implementation. Supabase repositories can be added behind the same protocols. Domain types do not import SwiftUI or Supabase.

See `docs/AUDIT_AND_IMPLEMENTATION_PLAN.md` for attachment findings, assumptions, milestones, and integration blockers.
