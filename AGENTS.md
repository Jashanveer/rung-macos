# Repository Guidelines

## Project Structure & Module Organization

Multiplatform SwiftUI + SwiftData app — one `Rung.xcodeproj`, bundle id `jashanveer.Rung`, ships to both iOS (18+) and macOS (15+) App Stores.

- `Rung/` — all shared cross-platform sources. Use `#if os(iOS)` / `#if os(macOS)` for platform-specific code within a file.
- `Rung-iOS-Sources/` — iOS-only files (no macOS counterpart): `PhoneTabScaffold`, `ScreenTimeService`, `SocialAppsPickerSheet`, `StreakActivityAttributes`, `StreakActivityController`, plus Resources (iOS entitlements, Info.plist). Excluded from macOS build via `EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]`.
- `RungWidgets/` — widgets bundle (Live Activity widget under `RungWidgets/iOS/`).
- `ScreenTimeMonitor/` — iOS DeviceActivity extension.
- `RungShared/` — cross-target shared types.
- `RungTests/`, `RungUITests/` — Swift Testing + XCTest.

## Build, Test, and Development Commands

```sh
open Rung.xcodeproj

# macOS
xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'platform=macOS' build

# iOS Simulator
xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'platform=iOS Simulator,name=iPhone 16' build

# Tests (host)
xcodebuild -project Rung.xcodeproj -scheme Rung test
```

## Coding Style & Naming Conventions

Use SwiftUI and SwiftData patterns already present in the project. Indent with 4 spaces. Use `PascalCase` for types, `camelCase` for properties and methods, and `private` for implementation details that do not need wider visibility. SwiftUI views should conform to `View` and keep UI in `body`; state should be scoped with `@State private var` when needed. Prefer `let` for constants, avoid force unwraps. Imports beyond `SwiftUI`/`SwiftData`/`Foundation` are common and expected for this app — `HealthKit`, `EventKit`, `WidgetKit`, `ActivityKit`, `FamilyControls`, `DeviceActivity`, `FoundationModels`, plus platform `AppKit`/`UIKit` (always behind `#if os(macOS)` / `#if os(iOS)`).

Prefer `#if os(...)` blocks for any platform-specific code within shared files. The dual-tree `Rung/macOS-Only/` directory has been retired — every file is now shared under `Rung/`, with iOS UX as canonical (it uses cross-platform SwiftUI APIs that compile on macOS too).

## Testing Guidelines

Add unit tests in `RungTests.swift` or nearby test files using Swift Testing's `@Test` and `#expect(...)`. Add end-to-end UI checks in the UI test target using `XCUIApplication`. Name tests after observable behavior, for example `@Test func addingHabitStoresTimestamp()`. Cover persistence and view-model logic with unit tests, and reserve UI tests for user workflows such as launch, add, edit, and delete.

## Commit & Pull Request Guidelines

Keep commits short, imperative, and focused (the project's history is full of good examples — `Drop EKAuthorizationStatus.authorized — deprecated since iOS 17 / macOS 14`, `Embed RungWidgets.appex on iOS too — was incorrectly macOS-only`). Pull requests should include a concise description, testing performed, screenshots for UI changes, and links to any related issue or task. Note any data model or SwiftData migration impact explicitly. When editing a file that has both `Rung/macOS-Only/` and `Rung-iOS-Sources/` copies, mention both in the PR diff.

## Agent-Specific Instructions

Keep changes limited to the requested task. Use Xcode project tooling for builds and diagnostics when available, and do not rewrite generated project files unless the change requires it.

## Integration Test Agent: `realtime-auth-validator`

Use this agent when asked to verify the implemented backend/app integration work:
- JWT refresh pipeline
- Repository layer + per-request states
- SSE real-time chat (`message.created`, `message.read`, `match.updated`)

### Preconditions
- Backend is running locally at `http://127.0.0.1:8080`.
- macOS app can be launched from Xcode.
- Two accounts are available (mentor + mentee), or can be created.

### Validation Workflow
1. Backend auth contract smoke test
- Register/login and confirm auth response includes `accessToken`.
- Call `POST /api/auth/refresh` and confirm a new `accessToken` is returned.
- Confirm protected endpoint access with refreshed token.

2. SSE contract smoke test
- Open stream:
  - `GET /api/accountability/matches/{matchId}/stream`
  - Headers: `Authorization: Bearer <accessToken>`, optional `Last-Event-ID`.
- Confirm stream yields heartbeat `ping` events.
- Trigger message send via `POST /api/accountability/matches/{matchId}/messages`.
- Confirm `message.created` arrives on active stream.
- Confirm read acknowledgment via `POST /api/accountability/matches/{matchId}/read` emits `message.read`.
- Confirm match lifecycle actions emit `match.updated`.

3. macOS app behavior test
- Launch two app windows/sessions (mentor and mentee).
- Send message in window A and verify it appears in window B within ~1 second.
- Temporarily disconnect/reconnect backend and verify stream reconnects and `refreshDashboard()` fallback runs on reconnect.
- Verify app no longer depends on manual post-send dashboard refresh for message propagation.

4. Request state verification (app layer)
- Validate `HabitBackendStore` request states transition correctly:
  - `authRequestState`
  - `dashboardRequestState`
  - `messageRequestState`
  - `streamRequestState`
- Validate `isSyncing` reflects any in-flight request state.

### Pass Criteria
- Refresh token flow works without forced logout.
- SSE stays connected with heartbeats and reconnect support.
- Chat updates are real-time across sessions (~1s target).
- Request-state driven loading/error behavior is consistent.
- Build passes for macOS app after validation.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
|------|----------|
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.
