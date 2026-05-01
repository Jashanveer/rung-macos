# Rung — iOS (iPhone) Design Brief

**Audience:** Claude Design
**Goal:** Design the iPhone version of Rung so it mirrors the structure and behavior of the shipped macOS app. We are **not** reinventing the product. The macOS app is the source of truth; you are producing the iPhone adaptation.

---

## 1. Product in one paragraph

**Rung** ("Form the habits that form you.") is a minimal, Liquid-Glass habit tracker. You add habits or tasks, check them off once per day, and build streaks. A companion accountability layer matches you with a mentor/mentee, shows a social feed, runs weekly challenges, and awards XP / coins / streak-freeze tokens. Everything is driven by a simple `Habit` model with a list of completed `yyyy-MM-dd` day keys; SwiftData stores it locally and syncs with a Spring Boot backend.

---

## 2. Non-negotiable design principles (inherited from macOS)

Preserve these on iPhone — they are the identity of the product.

1. **Liquid Glass surfaces.** All cards, panels, and floating controls use the `cleanShotSurface` / `liquidGlassBackground` treatment: translucent, lightly tinted, subtle stroke, soft shadow. On iOS 26 this maps directly to the same `glassEffect` API used on macOS 26.
2. **Spring motion only.** Every transition uses `.spring(response:dampingFraction:)`. No linear, no default ease. Panels enter from their anchor point (scale from near-zero toward the edge/handle they came from) like macOS Dock icons.
3. **Completed habits become ambient.** When a habit is checked off, its card morphs (matched geometry) into a floating "done pill" that drifts in the background. The main list only shows what's still pending. When the list is empty or fully complete, the add bar and greeting center on screen.
4. **Greeting is AI-generated.** The top-of-screen greeting comes from `FoundationModels` on-device (macOS 26+). Same behavior on iOS 26.
5. **Characters.** If the user has a mentor or mentees, a looping video character ("walker") animates in the corner. These are real `.mov` files played via `LoopingVideoView`.
6. **System-respectful.** Respect Dark Mode, Dynamic Type, Reduce Motion, and iOS safe areas (notch / Dynamic Island / home indicator).
7. **Palette & type.** Pull directly from `CleanShotTheme.swift` — do not introduce a new color system. Accent, success, warning, gold, violet, and the control/elevated surface tokens are already defined.

---

## 3. macOS structure → iPhone translation targets

The macOS app is one window with a three-region ZStack:

```
 ┌──────────────────────────────────────────────────────────────┐
 │  [left edge handle: Social]   CENTER PANEL   [right handle]  │
 │                               (habits)        (Stats)        │
 │                                                              │
 │                     [bottom handle: Calendar]                │
 └──────────────────────────────────────────────────────────────┘
```

Center stays put; Stats slides in from the right, Social/Settings from the left, Calendar rises from the bottom. On iPhone these must become first-class destinations. Design each of the screens below.

### 3.1 Intro / cold-launch (`RungIntroView`)
- **macOS behavior:** app icon builds itself on screen in 4 steps, flies into the auth card as the login avatar via matched geometry, then a grid cascade wipes to reveal the dashboard.
- **iPhone ask:** same three beats (build → fly-into-auth → cascade reveal), adapted to portrait. Icon centered, larger build animation; auth card full-width with rounded top; cascade fills the screen.

### 3.2 Auth (`AuthViews`)
- **macOS behavior:** single floating glass card; sign-in / sign-up toggle; forgot password.
- **iPhone ask:** full-height sheet-like layout. Card content is the same; input fields use iOS keyboard types (`.emailAddress`, `.password`). Include "Sign in with Apple" placement if we add it later (leave room).

### 3.3 Onboarding (`OnboardingView`)
- **macOS behavior:** James Clear overview → starter-habit picker → finish. One-time, per user.
- **iPhone ask:** paged horizontal flow (swipe), page dots, large illustrations, one primary CTA per page pinned to bottom above the home indicator.

### 3.4 Main dashboard — Home (`CenterPanel`)
- **macOS behavior:** `TodayHeader` (AI greeting + date), `AddHabitBar` (text field + task/habit segmented toggle + add button), then either (a) empty state, (b) "All done for today" state, or (c) scrollable list of pending `HabitCard`s. Compact vs. expanded layout depending on whether any pending habits exist.
- **iPhone ask:** same three states on one screen.
  - Header + add bar pinned top.
  - List scrolls below.
  - Completed habits drift as ambient pills behind the list (keep `DoneHabitPillsBackground`).
  - Navigation: a tab bar or a top toolbar with three entry points — **Stats**, **Social**, **Calendar** — replacing the macOS edge handles.
- **Recommended:** iOS 26 `TabView` with 4 tabs (**Today**, **Stats**, **Social**, **Calendar**), each of which corresponds to one of the macOS regions below. Propose this, or a better alternative, in your response.

### 3.5 Stats / Progress (`StatsSidebar`)
- **macOS behavior:** 330pt-wide slide-in panel containing, in order: `ProfileIdentityCard`, `LevelHeroCard`, a 120pt hero streak ring ("X% today"), two streak pills (current, best), 2×2 stats grid (Habits / Done / XP / Freezes), Level & XP progress card, `WeeklyChallengeCard`, `RewardEligibilityCard`, `StreakFreezeCard`, `HabitClusterSummaryCard`.
- **iPhone ask:** a full-width scrolling screen with the same card stack in the same order. Hero ring stays visually dominant at the top. Cards stretch edge-to-edge with the usual iOS 16pt horizontal margin. 2×2 stats grid becomes 2 columns (not 1); keep it tight.

### 3.6 Social / Settings (`SettingsPanel`)
- **macOS behavior:** left-edge slide-in panel. Contents in order: "Social Circle" header, `AccountActionsCard` (sync / sign out / delete account), `MentorActionCard` (find / show mentor), `SocialSummaryCard`, `SocialFeedCard` (followers' recent checks), `FriendSuggestionsCard` (search + suggestions), `TimeRemindersCard` (per-habit reminder windows).
- **iPhone ask:** a full-width scrolling screen. Same card order. Account actions pinned near the bottom so destructive controls aren't the first thing seen. Treat this as the app's "You" tab — consider adding a top-right gear icon later for truly secondary settings, but not now.

### 3.7 Calendar (`CalendarSheet` + `YearPerfectCalendar`)
- **macOS behavior:** bottom sheet, up to 980pt wide, contains a year-at-a-glance grid of perfect days (heat-map style) plus a month drill-in.
- **iPhone ask:** full-screen sheet with a large drag handle at top. Year grid scrolls vertically; month detail opens via tap-into-month transition (scale from tapped cell). No horizontal paging required.

### 3.8 Habit card (`HabitCard`)
- **macOS behavior:** a row with title, 7-day dot strip, checkbox, optional cluster badge (morning/afternoon/etc.), hover state. Completing the card triggers a matched-geometry morph into a floating pill in the background.
- **iPhone ask:** same anatomy. Replace hover with press state (slight scale + tint). Completion triggers the same morph **and** a medium-strength haptic (`UIImpactFeedbackGenerator(.medium)`). Long-press opens an iOS context menu for delete / edit / reminder — do **not** use the macOS-style right-click.

### 3.9 Floating elements
- `FloatingCheckPill` (confirmation), `SpeechBubbleNudge` (mentor nudge toast), `ConfettiOverlay` (perfect-day celebration) — design iPhone positions that respect the tab bar and safe areas.

---

## 4. Cross-cutting interaction rules

- **Tap targets ≥ 44pt.**
- **Haptics:** light on selection, medium on habit complete, success on streak milestones. None when Reduce Motion / Reduce Haptics is set.
- **Scroll behavior:** use iOS rubber-band; hide indicators like macOS does (`.scrollIndicators(.hidden)`).
- **Keyboards:** avoid the keyboard covering the add bar. The add bar should float above the keyboard when focused.
- **Pull-to-refresh** on the Home tab triggers `onSync`.
- **Sheet ergonomics:** use iOS 26 sheet detents (medium, large) wherever a panel would otherwise be a slide-in on macOS.
- **Navigation:** iPhone is stack-based. A tab bar for the four top-level destinations; pushes inside each tab for drill-ins (e.g., a mentee detail from Social).

---

## 5. Visual system to inherit (do not redesign)

- **Colors:** `CleanShotTheme.accent`, `.success`, `.warning`, `.gold`, `.violet`, `.controlFill(for:)`, `.stroke(for:)`, `.surface(for:level:)`.
- **Typography:** SF Rounded for numeric / hero values, SF Pro for body. Sizes already in code: hero 28 bold rounded, headline 18 semibold rounded, body subheadline, captions.
- **Corner radii:** 8 (small control), 18 (elevated surface), 20 (card), continuous style.
- **Shadows:** soft, low-radius, never pure black; prefer the `cleanShotSurface` shadow value (radius ~18 for elevated).
- **App icon:** 4×4 grid of rounded squares (blue + gold accent) over a dark squircle. Do not redesign the mark; reuse.

---

## 6. What NOT to change

- The data model (`Habit` with `completedDayKeys: [String]`, `entryType`, `isTaskCompleted`, `locationContext`, `pendingCheckDayKey`, etc.).
- The feature set. Do not invent new tabs, gamification mechanics, or AI features. If you see a gap, leave it as a visual placeholder and flag it in your notes.
- The brand name, tagline, or icon.
- The backend API surface (`AccountabilityDashboard` shape). Your designs must be expressible from fields that already exist on that response.

---

## 7. Platform-adaptation notes we already know

These exist in the iOS fork (`~/Documents/Rung-iOS`). Design with them in mind — do not design around them as if they're open questions.

- iOS 26.4 minimum; `@MainActor` by default; bundle id `jashanveer.Rung-iOS`.
- Shared App Group `group.jashanveer.Rung` drives widgets. iPhone widgets (Home + Lock Screen) are planned — please include designs for **small**, **medium**, and **lock-screen rectangular** widgets showing: today's progress %, current streak, and next pending habit.
- Live Activity for "streak in progress today" is planned — design the compact, expanded, and minimal Dynamic Island states.
- `LoopingVideoView` already has an iOS `UIViewRepresentable` twin; mentor/mentee characters render identically.

---

## 8. Deliverables requested from Claude Design

For each screen in §3 plus §7 widgets and Live Activity:

1. **High-fidelity mockups** in light and dark mode, at iPhone 16 Pro size (393×852), and one oversized device check at iPhone 16 Pro Max.
2. A **motion spec** (no video required) — list each transition, which spring parameters, which element uses matched geometry, and what the haptic trigger is.
3. A **component inventory** mapping each iPhone component back to the macOS SwiftUI struct it descends from (so we can reuse the view code where possible).
4. An **open questions** section for anything you had to guess.

Keep the output focused on iPhone. iPad can come later.

---

## 9. Reference files in the macOS repo (`~/Documents/Rung/Rung/`)

- Root scaffold: `ContentView.swift`, `ContentViewScaffold.swift`
- Center + habits: `CenterPanel.swift`, `HabitViews.swift`, `HabitCard` (inside `HabitViews.swift`)
- Right panel: `StatsSidebar.swift`
- Left panel: `SettingsPanel.swift`
- Bottom sheet: `CalendarViews.swift`
- Intro + auth + onboarding: `RungIntroView.swift`, `RungTransition.swift`, `AuthViews.swift`, `OnboardingView.swift`
- Visual system: `CleanShotTheme.swift`, `CleanShotStyle.swift`
- Floating elements: `FloatingCheckPill.swift`, `SpeechBubbleNudge.swift`, `ConfettiOverlay.swift`, `EdgePanelHandle.swift`
- Data + sync: `Habit.swift`, `HabitMetrics.swift`, `HabitBackend.swift`, `SyncEngine.swift`
- Icon source: `RungIconView.swift`, `Assets.xcassets/AppIcon.appiconset/`

End of brief.
