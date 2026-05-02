# RungWatch — Integration Notes

This is the watchOS companion to Rung. It does **not** run its own SwiftData
store; the iPhone is the source of truth and pushes a `WatchSnapshot` over
WatchConnectivity. The Watch sends back `logHabit` / `toggleHabit` messages
that the iPhone applies to SwiftData and re-broadcasts.

## What's wired up

- **Target setup** (`Rung.xcodeproj/project.pbxproj`)
  - New `RungWatch` native target — `com.apple.product-type.application`,
    `SDKROOT = watchos`, `WATCHOS_DEPLOYMENT_TARGET = 11.0`,
    `PRODUCT_BUNDLE_IDENTIFIER = jashanveer.Rung.watchkitapp`,
    `TARGETED_DEVICE_FAMILY = 4`,
    `SUPPORTED_PLATFORMS = "watchos watchsimulator"`.
  - Auto-generated scheme `RungWatch`.
  - Embedded into the iOS Rung target via a `PBXCopyFilesBuildPhase`
    ("Embed Watch Content", `dstSubfolderSpec = 16`,
    `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`) with `platformFilter = ios`
    so macOS Rung does **not** try to embed it.
  - Target dependency on `RungWatch` from `Rung` is also gated by
    `platformFilter = ios`.
  - Uses Xcode's modern `PBXFileSystemSynchronizedRootGroup` so any file
    you drop under `RungWatch/` automatically becomes part of the target.
  - Shares `RungShared/` so `WatchSnapshot.swift` compiles into both ends.

- **Watch UI** (`RungWatch/`)
  - `RungWatchApp.swift` — `@main`, instantiates the shared `WatchSession`.
  - `ContentView.swift` — five vertically-paged tabs via
    `.tabViewStyle(.verticalPage)`. The Habits tab is the only one with
    its own `NavigationStack` (it drills into detail views).
  - `Views/HabitsTab.swift` — pending list with HealthKit-auto rows
    (♥ AUTO badge), focused gold tint on the next manual habit.
  - `Views/CalendarTab.swift` — month grid heatmap; today is gold-bordered.
  - `Views/StatsTab.swift` — level pill, XP bar, 4-stat grid (DONE, BEST,
    RANK, FREEZE).
  - `Views/FriendsTab.swift` — leaderboard with current-user gold focus.
  - `Views/AccountTab.swift` — avatar, display name, @handle, three glass
    rows (Health sync, Notifications, iPhone app chevron).
  - `Views/HabitDetailView.swift` — manual habit drill-in. Crown
    rotation increments a counter, fires a `.click` haptic per +1, and
    sends `WCSession.sendMessage(["action": "logHabit", ...])` back to
    the phone.
  - `Views/HealthDetailView.swift` — HealthKit drill-in. Read-only;
    shows the synced number, a 100% progress bar, and "Synced Nm ago".
  - `Theme/WatchTheme.swift` — `CleanShotTheme` palette ported to flat
    hex constants matching the design HTML.
  - `Connectivity/WatchSession.swift` — `WCSessionDelegate`; receives
    snapshots via `didReceiveApplicationContext` /
    `didReceiveMessage` / `didReceiveUserInfo` and exposes them via
    `@Published var snapshot`.
  - `Connectivity/DataModel.swift` — canonical-emoji fallback table.

- **Shared transport** (`RungShared/WatchSnapshot.swift`)
  - `WatchSnapshot` struct with pending/completed habits, metrics,
    leaderboard, calendar heatmap, account info.
  - `WatchMessageKey` / `WatchMessageAction` constants for the small
    Watch → iPhone command vocabulary (`logHabit`, `toggleHabit`,
    `requestSnapshot`).

- **iPhone bridge** (`Rung-iOS-Sources/WatchConnectivityService.swift`)
  - Whole file wrapped in `#if os(iOS)` so macOS Rung skips it
    (additionally, the `Rung-iOS-Sources/` folder is excluded from the
    macOS slice via `EXCLUDED_SOURCE_FILE_NAMES[sdk=macosx*]`).
  - Activates `WCSession` once at app launch (called from `RungApp.init`).
  - Builds a `WatchSnapshot` from the live `[Habit]` and the optional
    `HabitBackendStore.dashboard`.
  - Debounces pushes 1s via `Timer.scheduledTimer` and dedupes
    byte-identical payloads.
  - Hooked into `WidgetSnapshotWriter.refresh()` so every habit-state
    change auto-broadcasts to the Watch (no extra wiring at the call
    sites).
  - Inbound `logHabit` / `toggleHabit` messages run a fresh
    `ModelContext` against the shared container, mutate the matching
    habit, save, and force a fresh push back.

- **App startup** (`Rung-iOS-Sources/RungApp.swift`)
  - `WatchConnectivityService.shared.start(container:)` is called once
    inside the `MainActor.assumeIsolated` block, gated by `#if os(iOS)`.

## What you must do manually in Xcode

1. **Install the watchOS 26.4 platform component.** This dev environment
   ships with the SDK but not the simulator runtime. In Xcode:
   `Settings → Components → watchOS 26.4 → Get`.
   Without this, `xcodebuild -scheme Rung` (iOS) refuses to start
   because of the embedded watch app, and `xcodebuild -scheme RungWatch`
   reports "no eligible destinations". Once installed, both work.

2. **Verify signing for the new target** the first time you open the
   project in Xcode. The target inherits `DEVELOPMENT_TEAM = YLN8JUVVX3`
   and `CODE_SIGN_STYLE = Automatic`, so Xcode should provision it
   without intervention. If it doesn't, re-tick "Automatically manage
   signing" on the Signing & Capabilities tab for `RungWatch`.

3. **App icon.** `RungWatch/Assets.xcassets/AppIcon.appiconset/` is
   currently a placeholder slot. Drop a 1024×1024 watchOS icon there
   before submitting to TestFlight.

4. **No new entitlements file is required** — WatchConnectivity does not
   need an entitlement, and the Watch app has no HealthKit / push of its
   own (the iPhone owns those).

## What's deferred

- **Complications / watch-face widgets** — out of scope per the spec.
- **Voice commands** — explicitly removed per the spec.
- **Independent watchOS HealthKit reads** — the Watch displays whatever
  the iPhone has already verified; it does not poll HealthKit on its
  own.
- **Rich onboarding / sign-in on the watch** — the watch assumes the
  iPhone is signed in; an unauthenticated user gets the placeholder
  account row.
- **Friends mutation from the watch** — leaderboard is read-only.
- **Tier-weighted leaderboard scoring on the watch** — same as iPhone:
  the visible score is the raw `score`. When the backend turns on
  `verifiedScore` we'll surface that here.

## Build & run

```sh
# Watch alone (requires watchOS 26.4 platform installed)
xcodebuild -scheme RungWatch \
    -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
    build

# iOS Rung (now embeds the watch app — also requires watchOS platform)
xcodebuild -scheme Rung \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    build

# macOS Rung (does not embed the watch app — works without watchOS platform)
xcodebuild -scheme Rung \
    -destination 'platform=macOS' \
    build
```

## Known agent-side build state at hand-off

- macOS Rung: **builds clean**.
- Type-check of the entire Watch source tree against
  `watchsimulator26.4` SDK with `swiftc -typecheck`: **clean**.
- iOS Rung scheme + RungWatch scheme: **could not be exercised in this
  worktree** because the watchOS 26.4 simulator runtime isn't installed
  in the local Xcode (`xcodebuild` reports "watchOS 26.4 must be
  installed"). Once you run Xcode → Settings → Components → install
  watchOS 26.4, both schemes should build with no further changes.
