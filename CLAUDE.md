# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```sh
# macOS build
xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'platform=macOS' build

# iOS Simulator build
xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests (host platform)
xcodebuild -project Rung.xcodeproj -scheme Rung test

# Open in Xcode
open Rung.xcodeproj
```

When running inside Xcode, prefer `BuildProject` and `RunAllTests`/`RunSomeTests` MCP tools. Use `XcodeRefreshCodeIssuesInFile` for fast compile-error checking without a full build.

## Architecture

**Multiplatform SwiftUI + SwiftData app** — the same source builds for **iOS 18+** (`IPHONEOS_DEPLOYMENT_TARGET = 18.0`) and **macOS 15+** (`MACOSX_DEPLOYMENT_TARGET = 15.0`) under one bundle id `jashanveer.Rung`.

### Targets

| Target | Source root | Notes |
|---|---|---|
| `Rung` | `Rung/` (synchronized folder) | Main app; both iOS + macOS |
| `Rung-iOS-Sources` | `Rung-iOS-Sources/` | iOS-only overrides for files that diverge from macOS, plus iOS-only views (`PhoneTabScaffold`, `Haptics`, `StreakActivity*`, etc.) |
| `RungWidgets` | `RungWidgets/` | Widgets bundle (StreakWidget, TodayRingWidget, ChecklistWidget, LeaderboardWidget, etc.). iOS Live Activity widget lives under `RungWidgets/iOS/`. |
| `ScreenTimeMonitor` | `ScreenTimeMonitor/` | iOS DeviceActivity extension for Screen Time verification. |
| `RungShared` | `RungShared/` | Cross-target types (`WidgetSnapshot`, `ToggleHabitIntent`, `FocusActivityAttributes`). |
| `RungTests` / `RungUITests` | `RungTests/`, `RungUITests/` | Swift Testing + XCTest. |

### Source-tree layout

Build-time platform routing is a single `EXCLUDED_SOURCE_FILE_NAMES` SDK rule in the pbxproj:

- `[sdk=macosx*] = "Rung-iOS-Sources/*.swift"` — macOS skips iOS-only files

Both targets compile everything under `Rung/` (no subdirectories carved out per-platform). For platform-specific code in shared files, use `#if os(iOS)` / `#if os(macOS)` blocks.

- `Rung/` — all shared multi-platform code. The `HabitBackendStore` orchestrator is split across 7 files (`HabitBackend.swift` plus six `HabitBackend+*.swift` extensions). Backend types are in `BackendNetworking.swift`, `BackendAPIClient.swift`, `BackendRepositories.swift`, `BackendSleepSnapshot.swift`. Calendar UI is split across `CalendarViews.swift`, `CalendarPhoneViews.swift`, `YearPerfectCalendarView.swift`, `CalendarToggles.swift`. Cross-platform helpers `PressHoverModifier` and `Haptics` live here.
- `Rung-iOS-Sources/` — pure iOS-only files (no macOS counterpart): `PhoneTabScaffold` (iPhone tab UI), `ScreenTimeService` (Family Controls), `SocialAppsPickerSheet`, `StreakActivityAttributes`, `StreakActivityController` (Live Activity), plus iOS Resources (entitlements, Info.plist).

There is no longer a `Rung/macOS-Only/` directory — every previously dual-tree file (HabitBackend, ContentView, BackendNetworking, ContentViewScaffold, RungApp, OnboardingView, AuthViews, HabitViews, SettingsPanel, RungIntroView, RungTransition, RiveCharacterView, etc.) has been consolidated to a single shared file under `Rung/` with platform conditionals where needed. iOS UX is canonical (the iOS code uses cross-platform SwiftUI APIs that compile on macOS too).

## Feature surface

This is more than a single-window habit tracker. Major subsystems:

- **Habit + Task tracking** — `Habit.swift` (SwiftData `@Model`), per-toggle `HabitCompletion` evidence records, daily and weekly-target ("gym 5×/week") cadences, ISO-week math, task overdue penalties.
- **Verification (anti-cheat)** — `VerificationService.swift` (HKHealthStore actor), `AutoVerificationCoordinator.swift`, `CanonicalHabits.swift` (fuzzy title → canonical-key matcher with Levenshtein typo tolerance). Tier-weighted points: `auto` × 10, `partial` × 5, `selfReport` × 1.
- **Backend sync** — `BackendNetworking.swift` (types: `RequestState`, `RetryPolicy`, `ResponseCache`, `BackendSession`, `BackendAuthTokens`, `UserPreferences`, etc.), `BackendAPIClient.swift` (actor — auth/session/JWT refresh), `BackendRepositories.swift` (`AuthRepository`, `HabitRepository`, `DeviceRepository`, `PreferencesRepository`, `AccountabilityRepository`), `BackendSleepSnapshot.swift`. The orchestrator `HabitBackendStore` is split across `HabitBackend.swift` (class shell + init + session + error handling) and feature extensions: `HabitBackend+Auth.swift`, `HabitBackend+Habits.swift`, `HabitBackend+Verification.swift`, `HabitBackend+Accountability.swift`, `HabitBackend+Preferences.swift`, `HabitBackend+SSE.swift`. Plus `SyncEngine.swift` (reconcile + outbox), `KeychainSessionStore.swift`, `NetworkMonitor.swift`.
- **Mentor/Mentee accountability** — `ChatMessageRow.swift`, `MentorChatBubble.swift`, `MenteeChatBubble.swift`, SSE event stream (`message.created`, `message.read`, `match.updated`).
- **Focus mode** — `FocusMode.swift`, `FocusAudioPlayer.swift`, `FocusAudioLibrary.swift` (bundled `walk-bruce-01.mov`, `walk-jazz-01.mov`), `FocusStatusBar.swift`, `FocusLiveActivity.swift`.
- **Calendar + Sleep + Energy** — `CalendarService.swift` (EventKit), `CalendarViews.swift` (entry sheet + enums), `CalendarPhoneViews.swift` (iPhone perfect-days year/month views), `YearPerfectCalendarView.swift` (iPad/macOS calendar grid), `CalendarToggles.swift` (mode pickers); `SleepInsightsService.swift` + `+CrossDevice.swift` (HealthKit sleep + Apple Health export parser, chronotype learning), `EnergyForecast.swift` / `EnergyView.swift` (two-process model + acrophase shifting), `HabitTimingStats.swift`.
- **Widgets + Live Activities** — `RungWidgets/` bundle (StreakWidget, TodayRingWidget, ChecklistWidget, DashboardWidget, LeaderboardWidget, FriendsProgressWidget, MenteeViewWidget, WeeklyWidget, XPLevelWidget, CommandCenterWidget). iOS Live Activity for streak + focus.
- **Screen Time** (iOS) — `ScreenTimeService.swift` + `ScreenTimeMonitor` extension; verifies `screenTimeSocial` habit category.
- **AI** — `FoundationModels` framework on macOS 26+ for on-device nudges and frequency parsing, with graceful fallback.
- **Onboarding** — `OnboardingView.swift`, `AppleProfileSetupView.swift`, `RungIntroView.swift` (with `RiveCharacterView`, `LoopingVideoView`, `WalkerState`, `SpeechBubbleNudge`).
- **Auth** — `AuthViews.swift`, JWT refresh pipeline, Apple Sign-In, account deletion with stale-session self-heal.

## Data model essentials

`Habit` (`Habit.swift`) — single SwiftData `@Model`. Notable fields:

- `title`, `entryType` (`.habit` / `.task`), `createdAt`, `completedDayKeys: [String]` (`yyyy-MM-dd` keys).
- Sync: `backendId`, `updatedAt`, `syncStatus` (`pending`/`synced`/`failed`/`deleted`), `pendingCheckDayKey`, `pendingCheckIsDone`.
- Verification (additive, lightweight-migrating): `verificationTierRaw`, `verificationSourceRaw`, `verificationParam`, `canonicalKey`, `localUUID`.
- Frequency: `weeklyTarget` — nil for daily habits; `N` hides the habit from the list once that ISO week has `N` checks. `Habit.isSatisfied(on:)` implements the rest-budget math (perfect days credit `7 - weeklyTarget` rest days chronologically).
- Tasks: `dueAt`, `priorityRaw`, `overduePenaltyApplied`, `isArchived`.

Forward-compat invariant: every typed accessor (`verificationTier`, `verificationSource`, `priority`, `entryType`) falls back safely on unknown raw values so a forward-compatible client never crashes on a tier introduced later. `effectiveCanonical` — a two-tier lookup (`canonicalKey` → exact alias match) — recovers auto-verification when sync drops the metadata.

## Key Patterns

- **Liquid Glass** — `liquidGlassBackground` / `liquidGlassControl` view modifiers wrap macOS 26 / iOS 26 `glassEffect` API with `@available` checks and pre-26 `ultraThinMaterial` fallbacks.
- **Streaks** — `HabitMetrics.currentStreak` and `bestStreak` walk sorted `[String]` day keys backwards by calendar day. `Habit.isSatisfied(on:)` is the single source of truth for what counts as "complete" on a given day (handles weekly-target rest budget).
- **ISO week** — `Habit.weekKeys(containing:)` is Monday-first, min-4-days-in-first-week. Both client and backend agree on week boundaries across timezones.
- **Outbox sync** — `SyncEngine.reconcile(local:remote:)` returns `(toInsert, toUpdate, toDelete)`. Unsynced local rows (`backendId == nil`) are never deleted.
- **SSE** — chat stream parser handles `event:`/`data:`/`id:` lines, supports `Last-Event-ID` reconnect resume.
- **Spring animations** — `.spring(response:dampingFraction:)` for all interactive transitions.
- **Symbol effects** — `.contentTransition(.symbolEffect)` for SF Symbol toggles.
- **Hover/press states** — `PressHoverModifier` for cards/buttons (subtle scale + color shifts).

## Code Style

- 4-space indentation.
- PascalCase types, camelCase properties/methods.
- `private` for view structs that don't need wider visibility.
- Imports: `SwiftUI`, `SwiftData`, `Foundation`, `FoundationModels`, `HealthKit`, `EventKit`, `WidgetKit`, `ActivityKit`, `FamilyControls`, `DeviceActivity`, `AppKit` (macOS only — guard with `#if os(macOS)`), `UIKit` (iOS only).
- Use `#if os(iOS)` / `#if os(macOS)` for platform-specific code rather than maintaining parallel files where reasonable. (For files with large divergence — e.g. `AuthViews`, `SettingsPanel` — separate platform copies are still acceptable.)

## Design Philosophy

Native-feeling on each platform:

- Spring animations only — never linear or basic ease curves.
- Panels expand from their origin point like macOS Dock icons (scale from near-zero at anchor).
- Hover states (macOS) and press states (iOS) on interactive elements — subtle scale and color shifts.
- Respect system color scheme; bridge with `nsColor` (macOS) / `uiColor` (iOS).
- Symbol effects (`.contentTransition(.symbolEffect)`) for toggling SF Symbols.

## Testing

- Swift Testing (`@Test`, `#expect(...)`) for unit tests.
- XCTest + XCUIAutomation for UI tests.
- Existing coverage: `HabitMetrics`, `Habit` model + migrations, `SyncEngine.reconcile`, `RetryPolicy`, `ResponseCache`, SSE parsing, `CanonicalHabits` matcher (alias / token-set / fuzzy / Levenshtein), `WeeklyTarget` rest-budget, `VerificationService` self-report fallback.
- Coverage gaps worth filling: `HabitBackendStore` outbox flush, `AutoVerificationCoordinator`, non-self-report `VerificationService` paths (HealthKit stubs needed), `FrequencyParser`, `OverduePenaltyStore`, `HabitTimingStats`.

## Verification + weekly targets

Rung habits carry optional verification metadata so leaderboard scoring can distinguish HealthKit-confirmed completions from honor-system ones.

**Tiers** (`VerificationTier`): `.auto` (HealthKit / DeviceActivity confirmed) / `.partial` (some evidence) / `.selfReport` (honor system). Drives point multipliers.

**Sources** (`VerificationSource`): HealthKit identifiers (`healthKitWorkout`, `healthKitSteps`, `healthKitMindful`, `healthKitSleep`, `healthKitBodyMass`, `healthKitHydration`, `healthKitNoAlcohol`), `screenTimeSocial` (iOS Family Controls), `selfReport`. `verificationParam` carries the threshold or activity-type code.

**Where verification is wired**:

- Onboarding (`OnboardingView.swift`) — two-phase flow: habit staging → permissions step with HealthKit Enable button.
- Habit creation (`HabitViews.swift` → `AddHabitBar`) — after Add, shows an inline confirmation card offering a frequency picker (Daily / 3× / 5× / 7× per week) and a verify-with-Apple-Health toggle when `CanonicalHabits.match(userTitle:)` finds a match. Never auto-applied silently.
- Toggle path (`ContentView.swift` → `toggleHabit`) — on done→true transitions, calls `backend.verifyCompletion(habit:dayKey:modelContext:)` fire-and-forget.
- Auto-verified habits (`isAutoVerified`) can't be manually toggled — `AutoVerificationCoordinator` watches HealthKit and marks them done. Long-press "Mark done manually" records at `.selfReport` tier so leaderboard cheating cost is preserved.
- Perfect-day math (`HabitMetrics.swift`) uses `Habit.isSatisfied(on:)` so frequency habits count rest days up to their `(7 - weeklyTarget)` budget.

**Backend round-trip** — V13 migration adds the columns; `HabitService` persists/returns them; `HabitCheck` carries the tier/source that corroborated each check; `LeaderboardEntry` reserves a `verifiedScore` int. **Open follow-ups**: tier-weighted leaderboard scoring (auto × 10 / partial × 5 / self × 1) and a server-side canonical-registry validator — both require AccountabilityService changes that were out of scope for the initial pass.

## MCP Tools: code-review-graph

**This project has a knowledge graph. ALWAYS use the code-review-graph MCP tools BEFORE Grep/Glob/Read.** The graph is faster, cheaper (fewer tokens), and gives structural context (callers, dependents, test coverage) that file scanning cannot.

| Tool | Use when |
|------|----------|
| `detect_changes` | Reviewing code changes — risk-scored analysis |
| `get_review_context` | Need source snippets — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | High-level structure |
| `refactor_tool` | Planning renames, finding dead code |

The graph auto-updates on file changes via hooks. Fall back to Grep/Glob/Read only when the graph doesn't cover what you need.
