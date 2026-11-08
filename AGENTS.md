# Repository Guidelines

## Project Structure & Module Organization

Pulse is a native SwiftUI resource monitor for macOS 14+. `Pulse.xcodeproj` builds the app; `Package.swift` exposes the portable `SamplingCore` library for testing.

- `Pulse/Models/`: snapshots, resource projections, and presentation state.
- `Pulse/Sampling/`: system readers and sampling coordination.
- `Pulse/Views/`, `ViewModels/`, `MenuBar/`, and `Actions/`: UI, dashboard state, menu bar integration, and process termination.
- `Pulse/Assets.xcassets/`: app icons and colors.
- `Tests/SamplingCoreTests/`: XCTest suites.
- `docs/`: `PRD.md` (current scope), `TECH.md` (current implementation and smoke checklist), `RELEASE.md`, `specs/` (archived per-phase design drafts), `adr/` (metric and design decisions), and `agents/` workflows.

## Build, Test, and Development Commands

- `swift test`: build and test the portable core; does not compile the macOS app.
- `swift test --filter SamplingPaceTests`: run a focused suite.
- `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug build`: build the app with Xcode 15+ on macOS.
- For local execution, open `Pulse.xcodeproj`, select **Pulse → My Mac**, and Run. Debug uses ad-hoc signing; a signing team is optional.
- `./scripts/notarize.sh --preflight`: check release credentials. Follow `docs/RELEASE.md` for notarization and optional DMG packaging.

## Coding Style & Naming Conventions

Match existing Swift style: four-space indentation, `UpperCamelCase` types/files, and `lowerCamelCase` members. Keep functions focused, nesting shallow, and files within 500 lines. Use icons rather than emoji. No formatter or linter is configured.

Prefer minimal changes that preserve existing behavior. Before editing, confirm the problem is real, choose the simplest solution, and identify compatibility risks. Preserve missing/error states rather than substituting zero readings. Keep portable logic free of Darwin/AppKit dependencies.

When adding a Swift file, register it in both places:

- `Pulse.xcodeproj/project.pbxproj`: the project does not use synchronized folders, so new files are not picked up automatically.
- `Package.swift`: add portable files to `sources`; add Darwin/AppKit-only files under `Sampling/` or `MenuBar/` to `exclude`.

## Testing Guidelines

Use XCTest with `<Feature>Tests.swift` filenames and descriptive `test...` methods. Add regression coverage for behavior changes and run `swift test`. No numeric coverage threshold is configured.

`*WiringSourceTests` read app source as text through `WiringSourceText`, which finds files by type-name prefix. Renaming a type, moving a file, or changing locked copy can break them. When splitting a type, name extension files `TypeName+Topic.swift` (for example `MemoryDashboardVM+QuitSession.swift`).

CI (`.github/workflows/ci.yml`, `macos-15`) runs `swift test` and an unsigned Debug `xcodebuild`; both must pass.

UI and system-reader changes also need macOS smoke checks against the 「本机冒烟清单」 in `docs/TECH.md`.

## Commit & Pull Request Guidelines

Recent commits commonly use `feat:` or `docs:` with concise Chinese descriptions and references such as `(#68)`. Numbered phases keep the phase name, e.g. `feat: 二十八期进程内存改用内存占用口径 (#88)` or `二十三期：拆分超限的详情侧栏与内存页 VM (#75)`. Keep commits scoped. PRs should describe the resulting behavior, link the issue, report validation and limitations, and include screenshots for visible UI changes.

## Documentation

Keep docs current in the same PR as the change:

- User-visible behavior or data-metric changes: update the matching section of `docs/TECH.md`, and its smoke checklist when the check changes. Edit in place; do not append a new phase section.
- Scope changes: update `docs/PRD.md` and the feature list in `README.md`.
- Reversing an earlier metric or design decision: add an ADR under `docs/adr/`.
- `docs/specs/` is an archive. Add a new `NN-topic.md` draft there if a phase needs one, and register it in `docs/specs/README.md`; never rewrite old drafts beyond a superseded note at the top.

## Agent Workflows & Configuration

For issues/specs in `qqzhangyanhua/pulse`, follow `docs/agents/issue-tracker.md`; for triage labels, read `docs/agents/triage-labels.md`. Before domain exploration, follow `docs/agents/domain.md` for glossary and ADR handling.

Keep signing credentials in environment variables or Keychain. Follow `docs/RELEASE.md`; leave generated builds and credentials untracked.
