# Repository Guidelines

## Project Structure & Module Organization

Pulse is a native SwiftUI resource monitor for macOS 14+. `Pulse.xcodeproj` builds the app; `Package.swift` exposes the portable `SamplingCore` library for testing.

- `Pulse/Models/`: snapshots, resource projections, and presentation state.
- `Pulse/Sampling/`: system readers and sampling coordination.
- `Pulse/Views/`, `ViewModels/`, `MenuBar/`, and `Actions/`: UI, dashboard state, menu bar integration, and process termination.
- `Pulse/Assets.xcassets/`: app icons and colors.
- `Tests/SamplingCoreTests/`: XCTest suites.
- `docs/`: see Documentation below.

## Build, Test, and Development Commands

- `swift test`: build and test the portable core; does not compile the macOS app.
- `swift test --filter SamplingPaceTests`: run a focused suite.
- App build, same as CI (`.github/workflows/ci.yml` is the source of truth):
  `xcodebuild -project Pulse.xcodeproj -scheme Pulse -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- `./scripts/notarize.sh --preflight`: check release credentials. Release, signing, and DMG packaging: `docs/RELEASE.md`.

## Coding Style & Naming Conventions

Keep files within 500 lines. Use icons rather than emoji.

Preserve missing/error states rather than substituting zero readings. Keep portable logic free of Darwin/AppKit dependencies.

When adding a Swift file, register it in both places:

- `Pulse.xcodeproj/project.pbxproj`: the project does not use synchronized folders, so new files are not picked up automatically.
- `Package.swift`: add portable files to `sources`; add Darwin/AppKit-only files under `Sampling/` or `MenuBar/` to `exclude`.

## Testing Guidelines

Use XCTest with `<Feature>Tests.swift` filenames and descriptive `test...` methods. Add regression coverage for behavior changes.

`*WiringSourceTests` read app source as text through `WiringSourceText`, which finds files by type-name prefix. Renaming a type, moving a file, or changing locked copy can break them. When splitting a type, name extension files `TypeName+Topic.swift` (for example `MemoryDashboardVM+QuitSession.swift`).

UI and system-reader changes also need macOS smoke checks against the 「本机冒烟清单」 in `docs/TECH.md`.

## Before You Finish

A change is done when every item holds:

- `swift test` passes.
- The CI app build command above passes.
- Every new Swift file is registered in both `project.pbxproj` and `Package.swift`.
- Docs are updated per Documentation below.
- For UI or system-reader changes, the PR lists which 「本机冒烟清单」 items were run and which were skipped.

## Commit & Pull Request Guidelines

Recent commits commonly use `feat:` or `docs:` with concise Chinese descriptions and references such as `(#68)`. Numbered phases keep the phase name, e.g. `feat: 二十八期进程内存改用内存占用口径 (#88)` or `二十三期：拆分超限的详情侧栏与内存页 VM (#75)`. Keep commits scoped. PRs should describe the resulting behavior, link the issue, report validation and limitations, and include screenshots for visible UI changes.

## Documentation

`docs/` holds `PRD.md` (current scope), `TECH.md` (current implementation and smoke checklist), `RELEASE.md`, `adr/` (metric and design decisions), `specs/` (archive), and `agents/` workflows. Keep docs current in the same PR as the change:

- User-visible behavior or data-metric changes: update the matching section of `docs/TECH.md`, and its smoke checklist when the check changes. Edit in place; do not append a new phase section.
- Scope changes: update `docs/PRD.md` and the feature list in `README.md`.
- Reversing an earlier metric or design decision: add an ADR under `docs/adr/`.
- Source of truth, in order: code on `main`, `docs/adr/`, `docs/TECH.md` / `docs/PRD.md`, then `docs/specs/`. Never base a decision on an archived draft alone; confirm the rule still holds in code or `docs/TECH.md` first.
- `docs/specs/` is an archive. Add a new `NN-topic.md` draft there if a phase needs one, and register it in `docs/specs/README.md`; never rewrite old drafts beyond a superseded note at the top.

## Agent Workflows & Configuration

For issues/specs in `qqzhangyanhua/pulse`, follow `docs/agents/issue-tracker.md`; for triage labels, read `docs/agents/triage-labels.md`. Before naming a new concept or changing a metric or design rule, read the related ADRs in `docs/adr/` (see `docs/agents/domain.md`).

Keep signing credentials in environment variables or Keychain; leave generated builds and credentials untracked.
