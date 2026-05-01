# Multiplatform Merge — Handoff

**Branch:** `feat/multiplatform-merge`
**Goal:** Single Xcode project with one app record (`jashanveer.Rung`) shipping to both iOS and macOS App Stores.

## What's already done (in this branch)

1. ✅ Branched from `main` as `feat/multiplatform-merge`.
2. ✅ All iOS source files staged outside the synchronized `Rung/` folder so they don't break the macOS build:
   - `Rung-iOS-Sources/` — 7 iOS-only Swift files + 25 iOS versions of files that diverge from macOS + iOS entitlements/Info.plist under `Resources/`
   - `RungWidgets-iOS-Sources/FocusLiveActivityWidget.swift` — iOS-only Live Activity widget
   - `ScreenTimeMonitor/` — full iOS extension target (DeviceActivityMonitor)
3. ✅ macOS build still passes: `xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'platform=macOS' build` — `BUILD SUCCEEDED`.
4. ✅ The `Rung.xcodeproj` is **already mostly multiplatform-ready**:
   - `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`
   - `IPHONEOS_DEPLOYMENT_TARGET = 18.0`
   - `MACOSX_DEPLOYMENT_TARGET = 15.0`
   - `PRODUCT_BUNDLE_IDENTIFIER = jashanveer.Rung` (clean, no `-iOS` suffix)
   - `TARGETED_DEVICE_FAMILY = "1,2,7"` (iPhone + iPad + Vision)
   - The `Rung` scheme already lists iPhone Simulator destinations.

## Current project state — what builds, what doesn't

| Destination | Status |
|---|---|
| `platform=macOS` | ✅ builds |
| `platform=iOS Simulator` | ❌ fails — existing macOS files (`RungApp.swift`, `OnboardingView.swift`) `import AppKit` without `#if os(macOS)` guards. Staged iOS files aren't yet wired into a target. |

## Why the iOS work has to happen in Xcode UI (not CLI)

The project uses **Xcode 16 synchronized folders** (`PBXFileSystemSynchronizedRootGroup`). Files in `Rung/` auto-compile for whatever target the folder is attached to. When I tried staging iOS files inside `Rung/iOS/`, Xcode auto-picked them up and the build failed with duplicate-output errors (e.g., two `ContentView.swift` files producing the same `.stringsdata`).

The correct fix is to use **per-file platform filters** on synchronized folders — and that UI is in Xcode, not safely scriptable in `.pbxproj` via text edits.

## What you need to do in Xcode (~1–2 hours, walked through together)

### Step 1: Open in Xcode
```sh
open /Users/jashanveer/Documents/Rung/Rung.xcodeproj
```
Make sure you're on branch `feat/multiplatform-merge`.

### Step 2: Decide the target structure

Two reasonable options:

**Option A — single target, platform filters (recommended, less work):**
- Keep one `Rung` target that builds for both iOS and macOS
- Use platform filters to gate each platform-divergent file
- Pro: simpler, single scheme, single Universal Purchase
- Con: every divergent file needs `#if os()` wrap OR per-file membership filter

**Option B — two targets (Rung-iOS, Rung-macOS), shared core target:**
- Create a `RungCore` framework target with the 30 identical files
- `Rung-iOS` target compiles `Rung-iOS-Sources/` + `RungCore`
- `Rung-macOS` (current `Rung`) compiles `Rung/` + `RungCore`
- Pro: Cleaner separation, no platform filters needed
- Con: More target restructuring, framework setup

**My recommendation: Option A.** It maps cleanest onto the synchronized-folder structure already in the project.

### Step 3 (Option A path): Platform-filter the staged iOS sources

1. In Xcode, right-click the `Rung` group → **Add Files to "Rung"…**
2. Select the `Rung-iOS-Sources/` folder. Choose **"Create folder reference"** (blue folder icon, synchronized).
3. After it's added, select the new folder in the navigator → **File Inspector (right panel)** → **Target Membership**: only `Rung` checked.
4. With the `Rung-iOS-Sources/` folder still selected, find the **Platforms** dropdown in the file inspector. Set to **iOS only** (uncheck macOS).
5. Repeat for `RungWidgets-iOS-Sources/FocusLiveActivityWidget.swift` — add to `RungWidgets` target, mark iOS-only.

### Step 4: Platform-filter the existing macOS-divergent files

Same divergent file names exist in both `Rung/` (macOS versions) and `Rung-iOS-Sources/` (iOS versions). To prevent duplicate-symbol errors, mark these specific files in `Rung/` as **macOS-only** in the file inspector:

```
AppleProfileSetupView.swift   AuthViews.swift            AutoVerificationCoordinator.swift
BackendNetworking.swift       CenterPanel.swift          ContentView.swift
ContentViewScaffold.swift     EdgePanelHandle.swift      HabitBackend.swift
HabitViews.swift              LoopingVideoView.swift     MenteeChatBubble.swift
MentorChatBubble.swift        OnboardingView.swift       PrivacyInfo.xcprivacy
RiveCharacterView.swift       RungApp.swift              RungIntroView.swift
RungTransition.swift          SettingsPanel.swift        SpeechBubbleNudge.swift
StatsSidebar.swift            VerificationHelpSheet.swift VerificationService.swift
WalkerState.swift
```

(25 files total. Select them all in the navigator with cmd-click, then set Platforms → macOS only in the file inspector.)

### Step 5: Add the ScreenTimeMonitor extension target

1. **File → New → Target → iOS → Application Extension → DeviceActivityMonitor Extension**
2. Product name: `ScreenTimeMonitor`
3. Bundle ID: `jashanveer.Rung.ScreenTimeMonitor`
4. After creation, **delete** the auto-generated `ScreenTimeMonitor` folder Xcode created
5. Right-click the new target's group → Add Files → select the existing `ScreenTimeMonitor/` folder at project root, "Create folder reference"
6. Make sure target membership = `ScreenTimeMonitor` only (NOT Rung)
7. Set Platforms → iOS only on the target

### Step 6: Configure per-platform Info.plist + entitlements

The Rung target build settings need:
- `INFOPLIST_FILE[sdk=iphoneos*]` = `Rung-iOS-Sources/Resources/Info-iOS.plist`
- `INFOPLIST_FILE[sdk=iphonesimulator*]` = `Rung-iOS-Sources/Resources/Info-iOS.plist`
- `INFOPLIST_FILE[sdk=macosx*]` = `Rung/Info.plist` (already set)
- `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` = `Rung-iOS-Sources/Resources/Rung-iOS.Release.entitlements` (Release config)
- Same for Debug config / iphonesimulator SDK

Set these in: **Project navigator → Rung target → Build Settings → search "Info.plist file" / "Code signing entitlements"**, then click the `+` next to "Any SDK" to add SDK-conditional values.

### Step 7: Try the iOS build

```sh
xcodebuild -project Rung.xcodeproj -scheme Rung -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40
```

You'll likely see new compile errors — UIKit imports needing iOS-specific frameworks, missing capabilities, etc. We'll fix these together as they come up.

## After it builds — what remains

- Wire up Live Activity widget in `RungWidgetsBundle.swift` with `#if os(iOS)` guard
- Verify HealthKit permissions on iOS (entitlements were copied from iOS project, should be intact)
- Verify SwiftData container works on both — same store URL strategy
- Test on actual iPhone if possible (Family Controls needs a real device)

## Critical: do NOT delete the `Rung-iOS/` and `Rung/` source projects

They're your backups until the merged version is shipping in TestFlight. Don't delete them.

## Files staged in this commit

```
Rung-iOS-Sources/
├── (7 iOS-only Swift files)
├── (25 iOS versions of divergent files)
└── Resources/
    ├── Info-iOS.plist
    ├── Rung-iOS.Debug.entitlements
    └── Rung-iOS.Release.entitlements
RungWidgets-iOS-Sources/
└── FocusLiveActivityWidget.swift
ScreenTimeMonitor/
├── DeviceActivityMonitorExtension.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
└── ScreenTimeMonitor.entitlements
```
