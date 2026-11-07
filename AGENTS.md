# Repository Guidelines

## Project Structure & Module Organization

Pulse is a native SwiftUI resource monitor for macOS 14+. `Pulse.xcodeproj` builds the app; `Package.swift` exposes the portable `SamplingCore` library for testing.

- `Pulse/Models/`: snapshots, resource projections, and presentation state.
- `Pulse/Sampling/`: system readers and sampling coordination.
- `Pulse/Views/`, `ViewModels/`, `MenuBar/`, and `Actions/`: UI, dashboard state, menu bar integration, and process termination.
- `Pulse/Assets.xcassets/`: app icons and colors.
- `Tests/SamplingCoreTests/`: XCTest suites.
- `docs/`: requirements, technical design, release instructions, and agent workflows.

## Build, Test, and Development Commands

- `swift test`: build and test the portable core; does not compile the macOS app.
- `swift test --filter SamplingPaceTests`: run a focused suite.
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug build`: build the app with Xcode 15+ on macOS.
- For local execution, open `Pulse.xcodeproj`, select **Pulse → My Mac**, and Run. Debug uses ad-hoc signing; a signing team is optional.
- `./scripts/notarize.sh --preflight`: check release credentials. Follow `docs/RELEASE.md` for notarization and optional DMG packaging.

## Coding Style & Naming Conventions

Match existing Swift style: four-space indentation, `UpperCamelCase` types/files, and `lowerCamelCase` members. Keep functions focused, nesting shallow, and files within 500 lines. Use icons rather than emoji. No formatter or linter is configured.

Prefer minimal changes that preserve existing behavior. Before editing, confirm the problem is real, choose the simplest solution, and identify compatibility risks. Preserve missing/error states rather than substituting zero readings. Keep portable logic free of Darwin/AppKit dependencies; update the explicit source list in `Package.swift` when adding core files.

## Testing Guidelines

Use XCTest with `<Feature>Tests.swift` filenames and descriptive `test...` methods. Add regression coverage for behavior changes and run `swift test`. No numeric coverage threshold is configured. UI and system-reader changes also need macOS smoke checks against `docs/PRD.md` and the relevant `docs/TECH.md` checklist.

## Commit & Pull Request Guidelines

Recent commits commonly use `feat:` or `docs:` with concise Chinese descriptions and references such as `(#68)`. Keep commits scoped. PRs should describe the resulting behavior, link the issue, report validation and limitations, and include screenshots for visible UI changes.

## Agent Workflows & Configuration

For issues/specs in `qqzhangyanhua/pulse`, follow `docs/agents/issue-tracker.md`; for triage labels, read `docs/agents/triage-labels.md`. Before domain exploration, follow `docs/agents/domain.md` for glossary and ADR handling.

Keep signing credentials in environment variables or Keychain. Follow `docs/RELEASE.md`; leave generated builds and credentials untracked.
