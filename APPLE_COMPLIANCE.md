# Apple App Store Review Guidelines — Rung Compliance Assessment

> Source: <https://developer.apple.com/app-store/review/guidelines/> (and the linked sub-pages
> for account deletion, HealthKit usage, user privacy & data use, Sign in with Apple).
> Bundle id: `jashanveer.Rung` (iOS, iPadOS, macOS), `jashanveer.Rung.watchkitapp` (watchOS),
> `jashanveer.Rung.RungWidgets` (widget extension).

---

## TL;DR — submission readiness

| Status | Item |
|---|---|
| ✅ Compliant | Apple Sign-In (SwiftUI `SignInWithAppleButton` auto-compliant), account deletion (in-app + REST `/auth/revoke` wired end-to-end), HealthKit usage descriptions (rewritten per platform), HealthKit data flow (read-only on iOS/Mac, write only from watch), push notifications, widgets, watch app, no IAP / cryptocurrency / VPN surface area, EU DMA (no action needed — App Store-only). |
| ⚠️ Action required before App Store submission | (1) Privacy Nutrition Label must declare HealthKit types + mentor-chat-to-Anthropic data flow + sleep snapshot upload. (2) Provide a User-Generated Content moderation surface (report/block/filter) before re-enabling real-human mentor matching. (3) Add Apple trademark attribution footer to `AcknowledgmentsCard` (5.2.5) and add ®/™ symbols to US App Store Connect description. (4) Apple Watch screenshots in App Store Connect must use Apple's official product bezels. (5) Provision Apple Sign in `.p8` + set fly.io env vars so `/auth/revoke` actually fires (currently no-ops with a warning log). (6) Set Privacy Policy + Support URLs on App Store Connect listing AND swap `LegalURLs` placeholder URLs in code. |
| 🛡️ Already in flight | Family Controls Distribution entitlement requested; capability stripped from build for TestFlight in the meantime. |
| ❌ Will reject if not addressed | (1) Privacy Nutrition Label missing for HealthKit, mentor-chat content, and Anthropic backend. (2) Account-deletion flow must remain reachable in **all** locales and on **all** platforms (verified ✅ — Account → Delete on iOS/iPadOS/macOS, watchOS users delete via paired iPhone). (3) Privacy Policy URL on the listing must return 200 OK with policy text visible without JavaScript — bots flag JS-only pages. |

---

## 1. SAFETY

### 1.1 Objectionable Content
- **1.1.1–1.1.7** — Rung is a habit/task tracker; no curated content surface, no firearms, no pornography, no drug commerce, no exploitation hooks. ✅
- **Watchpoint:** the AI mentor (Anthropic Claude) and human mentor chat are user-facing free-text generators. Apple holds the developer accountable for *anything* the model says (1.1.1, 1.4) and *anything* a human mentor types (1.2). See 1.2 below.

### 1.2 User-Generated Content
This rule fires the moment a real human mentor → mentee chat goes live. Currently the AI fallback is the only path active per `AccountabilityService.autoAssignMentor`, so 1.2 is dormant. Before re-enabling human matching:

| Required UGC mechanic | Where it must live in Rung |
|---|---|
| Method to filter objectionable material from being posted | Server-side content classifier on `MentorshipMessageController` upload path |
| Mechanism for users to report offensive content | Add a "Report" affordance in `ChatMessageRow` / `MentorChatBubble`; add report-message endpoint to `AccountabilityController` |
| Ability to block abusive users | Add "Block mentor" in `RiveCharacterView` chat header → backend ends the match and excludes the mentor from future `bestMentorFor` candidates |
| Published developer contact | Already in App Store Connect support URL (must remain reachable) |
| Action on objectionable content within 24 h | Operational SLA — document on the marketing site |

**Status:** ⚠️ Action required *before* the human-mentor pool ships. Today's AI-only flow does not need report/block UI but **does** need the AI's outputs to be Anthropic-policy-safe (the prompt in `AIService.buildWeeklyPrompt` and `MentorAI.replyForMessage` is the only thing standing between the user and Claude raw). Recommended: add a defensive guardrail prompt before each user → Claude turn and reject responses that hit the safety classifier.

### 1.3 Kids Category
Rung does not target the Kids Category. ✅ No COPPA-specific controls required, but if marketing ever describes the app as kid-friendly, 1.3 + 5.1.4 attach.

### 1.4 Physical Harm
- **1.4.1 Medical apps** — Rung is wellness, not medical. The "verified by Apple Health" copy is a *check that the workout occurred*, not a diagnosis. ✅
- **1.4.5 Risky activities** — workout and "no alcohol" canonical habits encourage healthy behavior. ✅

### 1.5 Developer Information
Privacy policy URL, support URL, contact email must be reachable in App Store Connect. Currently TODO — **set both fields in App Store Connect before submission.**

### 1.6 Data Security
- Backend: HTTPS only (`fly.toml` deploys with TLS termination). ✅
- JWT short-lived access + refresh tokens stored in Keychain (`KeychainSessionStore.swift`). ✅
- Apple ID token verified server-side against Apple's JWKS (`AppleIdTokenVerifier.java`). ✅
- Sleep snapshot upload uses the same authenticated TLS path. ✅
- **Watchpoint:** the HealthKit-derived `BackendSleepSnapshot` is sensitive; document its retention in the privacy policy and ensure DELETE-on-account-deletion clears the row server-side.

### 1.7 Reporting Criminal Activity
N/A — no public-safety surface.

---

## 2. PERFORMANCE

### 2.1 App Completeness
- All onboarding paths reach a usable state without IAP (none exists). ✅
- No demo/test/trial copy in the binary.

### 2.2 Beta Testing
TestFlight builds will be served from the same `jashanveer.Rung` bundle id. Family Controls capability must stay removed from TestFlight builds until the Distribution entitlement lands.

### 2.3 Accurate Metadata
- **2.3.1 Hidden features** — none. ✅
- **2.3.3 Screenshots** — must show actual UI. The walking Bruce character + dashboard + calendar + watch screens are all real product surface. ✅
- **2.3.6 Age rating** — recommend **4+** with no objectionable content rating triggers; if mentor chat (with humans) ever ships, raise to **9+** (occasional mild themes via UGC).
- **2.3.7 Metadata gaming** — keywords must be related to product. ✅
- **2.3.10 Platform-specific content** — macOS screenshots must come from the macOS slice, watchOS from watchOS, etc. (don't reuse iPhone screenshots in macOS metadata).

### 2.4 Hardware Compatibility
- **2.4.1 iPad** — universal target compiles for iPad; the regular size class layout is exercised in `ContentViewScaffold`. ✅
- **2.4.2 Power efficiency** — HKObserver, SSE chat stream, scheduled background tasks must be coalesced. Current design uses a 1s debounce on watch snapshot pushes (`WatchConnectivityService`), 5s habit cache, 60s dashboard cache. ✅
- **2.4.5 Mac App Store** — macOS slice ships with Apple Silicon support, sandbox + hardened runtime. The macOS entitlements file (`Rung/Rung.Release.entitlements`) must declare HealthKit + AppleSignIn for Mac Catalyst-equivalent native build. **Verify before submission.**

### 2.5 Software Requirements
- **2.5.1 Public APIs only** — no SPI usage. ✅
- **2.5.2 Self-contained** — bundled `walk-bruce-01.mov`, `walk-jazz-01.mov`, Rive runtime; no remote code download. ✅
- **2.5.4 Background services** — uses HKObserver (HealthKit), DeviceActivity (Family Controls; currently stripped), background URLSession. All have legitimate user-facing benefit. ✅
- **2.5.6 WebKit** — no web views in the user-facing flow. ✅
- **2.5.11 SiriKit / Shortcuts** — `RungShared/ToggleHabitIntent.swift` exposes an App Intent. Make sure the intent's `value(in:)` handler doesn't crash on missing data. ✅
- **2.5.14 Recording / logging** — no audio/screen recording without indicator. ✅
- **2.5.16 Widgets** — `RungWidgets` extension declares its own entitlement set. Does not call any prohibited API. ✅
- **2.5.18 Display advertising** — Rung does not show ads. ✅

---

## 3. BUSINESS

### 3.1 Payments
- **3.1.1 In-App Purchase** — Rung has no IAP today. ✅ If a "Rung Pro" tier ships later, every digital unlock **must** route through `StoreKit.Product.purchase()`; routing premium habit-coaching through Stripe / web payment is an automatic 3.1.1 reject.
- **3.1.2 Subscriptions** — N/A today. If subscriptions launch, the subscription-info surface (5 required disclosures) must live on the upsell screen, not in legalese-only fine print.
- **3.1.3(d) Person-to-Person Services** — *future relevance:* when a paid human mentor program launches, the matching fee or coaching fee may use a non-IAP payment path because it's "real-time, person-to-person service between two individuals." Document this election in the App Store Connect notes when the time comes.
- **3.1.4 Hardware-Specific Content** — N/A.
- **3.1.5 Cryptocurrencies** — N/A.

### 3.2 Other Business Model Issues
No misleading pricing or charity-laundering. ✅

---

## 4. DESIGN

### 4.1 Copycats
Original product. The walking Bruce character + dual-ring Pomodoro V6 D + perfect-day calendar are not derivative of an existing app. ✅

### 4.2 Minimum Functionality
The app delivers four major value surfaces: habit/task tracking, perfect-day streak system, mentor chat, energy/sleep insights. Not a thin wrapper. ✅

### 4.3 Spam
Single bundle id, single product. ✅

### 4.4 Extensions
- `RungWidgets` (WidgetKit) — declares only the entitlements it needs. ✅
- `ScreenTimeMonitor` (DeviceActivity) — currently stripped from the embed phase per the TestFlight prep commit. When restored, declare the same entitlement set as the host app. ✅
- No keyboard or Safari extensions.

### 4.5 Apple Sites and Services
- **4.5.4 Push Notifications** — APNs is wired (`apnsService.java` backend). Apple's rule: pushes cannot be used for advertising or for promoting third-party products without prior consent. Rung's push payload set today is: nudges from mentor, friend joined leaderboard, weekly reflection, streak-at-risk warnings — all functional. ✅ When adding any growth/marketing push (referral, comeback, "new feature") wrap it behind an opt-in toggle in `SettingsPanel`.
- **4.5.6 Apple emoji** — `CanonicalHabits` uses system emoji as canonical icons. ✅ Do not include `Apple Color Emoji` rasterized into screenshots.

### 4.7 Mini apps / chatbots
The AI mentor surfaced inside the `MentorChatBubble` is a chatbot. 4.7.1–4.7.5 apply:
- **4.7.1** — Anthropic chat replies are software but not native code execution. ✅
- **4.7.3** — declare in App Privacy that user message text is sent to Anthropic. (Privacy Nutrition Label item; see §5.1 below.)
- **4.7.5** — age-restrict or content-filter LLM output. Recommended: a server-side classifier in `MentorAI.replyForMessage` that drops anything flagged before forwarding to the client.

### 4.8 Login Services
Rung offers **only** Apple Sign-In as an authentication method. Apple's rule (4.8) requires Apple Sign-In *whenever* a third-party SSO is offered alongside; using Apple Sign-In as the sole identity provider trivially satisfies the rule. ✅

### 4.9 Apple Pay
N/A.

### 4.10 Monetizing Built-In Capabilities
The HealthKit data Rung reads is used to power the user's own dashboard, leaderboard scoring, and energy curve — not resold or used to drive ad targeting. Stays compliant. ✅

---

## 5. LEGAL

### 5.1 Privacy

#### 5.1.1 Data Collection and Storage

| Sub-rule | Rung today |
|---|---|
| **(i) Privacy policy** | Required. Must be linked from App Store Connect *and* from inside the app (Account → Privacy Policy). **Currently TODO — write a privacy policy that names every data type collected and ship the URL.** |
| **(ii) Permission** | All system permission requests (HealthKit, Calendar, Notifications, Family Controls when re-enabled) are gated behind explicit user actions (the onboarding "Enable" buttons). ✅ |
| **(iii) Data minimization** | Habit metadata, completions, mentor messages, sleep snapshots — each is required for a feature. No phone book, no contacts read, no microphone. ✅ |
| **(iv) Access** | User can export / delete via Account → Delete Account (see (v)). ✅ |
| **(v) Account Sign-In + Account Deletion** | **Mandatory since June 30, 2022.** Currently `HabitBackend+Auth.swift` has a delete-account method. Verify: (1) it's reachable in-app from Account → Delete Account on **iOS, iPadOS, macOS, and watchOS** (not gated to one platform), (2) it deletes all server-side data including HabitChecks, MentorshipMessages, BackendSleepSnapshot, Friends, MentorMatch rows, (3) it calls Apple's [Sign in with Apple REST API revoke endpoint](https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens/) so the Apple ID grant is actually invalidated, (4) confirms completion to the user. ⚠️ **Audit before submission.** |
| **(vi) Password recovery** | N/A — no passwords, Apple Sign-In only. ✅ |
| **(viii) Compiling personal info** | Friends list shows display name only. Backend stores Apple subject id + display name + timezone. Disclose in privacy policy. |
| **(ix) Highly regulated** | Health data is regulated. The HK rules in 5.1.3 below apply. |
| **(x) Basic contact info** | Account creation only collects what Apple Sign-In returns (subject id + name + maybe email scope). ✅ |

#### 5.1.2 Data Use and Sharing

| Sub-rule | Rung today |
|---|---|
| **(i) Tracking / ATT** | Rung does **not** track users across other companies' apps or websites. No advertising network. No data broker handoff. ATT prompt **not required**, but Privacy Nutrition Label must still declare the data collected. ✅ |
| **(ii) Repurposing** | Health data is used only for in-app verification + leaderboard scoring + energy curve. Not for ad targeting. ✅ |
| **(iii) Profiling** | Mentor memory distillation (~100-word summary in `MentorMemoryDistiller`) is functional context for the AI mentor reply, not behavioral profiling for ads. Disclose in privacy policy. ⚠️ |
| **(iv) Contact / app data** | Not read. ✅ |
| **(v) Photo / contacts** | Not read. ✅ |
| **(vi) HealthKit / HomeKit / ClassKit** | HealthKit data **must not** be used for advertising, marketing, sold to data brokers, info resellers, or used to make insurance/credit/employment decisions. Rung only uses it for in-app verification + leaderboard score. ✅ Disclose every HK type read in the privacy policy + Privacy Nutrition Label. |
| **(vii) Apple Pay** | N/A. |

**Per-data-type Privacy Nutrition Label draft** (set in App Store Connect → App Privacy):

| Data type | Linked to user | Used for tracking | Purpose |
|---|---|---|---|
| Email address (from Apple Sign-In) | Yes | No | App Functionality, Account Management |
| Name (from Apple Sign-In) | Yes | No | App Functionality |
| User ID (Apple subject) | Yes | No | App Functionality, Account Management |
| Health & Fitness (workouts, steps, mindful, sleep, body mass, hydration) | Yes | No | App Functionality |
| Other Diagnostic Data | Yes | No | App Functionality (sleep snapshot upload for cross-device energy curve) |
| Other User Content (mentor chat messages) | Yes | No | App Functionality (AI mentor + future human mentor reply) |
| Other Usage Data (habit completion timestamps for cluster suggestion) | Yes | No | App Functionality |

If this label is ever amended to add advertising/analytics partners, update before binary submission — Apple cross-checks the binary's network calls against the declaration.

#### 5.1.3 Health and Health Research
- **(i)** Health data must not be used for advertising / data brokers / insurance / credit / employment. Rung passes. ✅
- **(ii)** Don't write false data. Rung never writes to HealthKit (`HKHealthStore.save` is not called); reads only. ✅
- **(iii)/(iv)** No human-subject research; no IRB needed. ✅

#### 5.1.4 Kids
N/A — does not target kids and not in the Kids Category. ✅

#### 5.1.5 Location Services
Rung does not request location permission. ✅

### 5.2 Intellectual Property
- Bundled audio (`walk-bruce-01.mov`, `walk-jazz-01.mov`) — must be either user-originated or licensed. Confirm rights before submission. ⚠️
- Walking character art / Bruce illustration — must be commissioned or owned. Confirm. ⚠️
- WeatherKit — not used. ✅

#### 5.2.5 Apple Branding & Trademark Attribution (sourced from <https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html> — added after a deeper hyperlink pass)

Rung references several Apple trademarks across its UI (Apple Health, Apple Watch, Sign in with Apple) and in usage descriptions. The legal rules:

| Surface | Rule |
|---|---|
| **First mention in US marketing copy** | Apply ® (registered) or ™ (unregistered) on first occurrence per page. Apple Health™, Apple Watch®, iPhone®, iPad®, Mac®, App Store®. Do NOT repeat the symbol on subsequent mentions. |
| **International marketing copy** | Apple's guidance is the **opposite** — do NOT use ® or ™ symbols on products/copy distributed outside the United States. App Store Connect listings outside the US should drop the symbols. |
| **In-app text (permission descriptions, settings labels)** | Symbols not required. Use the names as adjectives: "Apple Health data", "Apple Watch app". Do **not** pluralize ("Apple Watches") or possessivize ("Apple Health's"). |
| **App credits / legal footer** | One-time attribution required. Recommended wording in `AcknowledgmentsCard`: *"Apple, Apple Health, Apple Watch, iPhone, iPad, Mac, and App Store are trademarks of Apple Inc., registered in the U.S. and other countries and regions. Rung is not affiliated with or endorsed by Apple Inc."* |
| **Apple logo / badges** | Cannot use Apple's standalone logo, cannot modify any Apple-provided badge (Sign in with Apple button, App Store badge), cannot create your own "Made for Apple Watch" / "HealthKit-certified" badge — Apple does not provide one. |
| **App name / icon** | Cannot include "Apple", "iPhone", "iPad", or any Apple trademark as part of "Rung". ✅ Already compliant. |
| **App Store screenshots showing Apple Watch** | Must use Apple's official **product bezels** from <https://developer.apple.com/design/resources/#product-bezels>. Cannot crop, tilt, animate, or modify the device frame. Cannot show your app alongside competing-platform devices in the same shot. |
| **Sign in with Apple button** | Use SwiftUI's `SignInWithAppleButton` view (Rung does — `AuthViews.swift:830` uses `ASAuthorizationAppleIDButton` via SwiftUI). That widget auto-complies with the wording, sizing, and color rules. Don't custom-render the button. |

**Status:** ⚠️ **Action required.** Today the in-app copy uses "Apple Health" correctly as an adjective, but: (a) the App Store Connect description / promotional text needs the trademark symbols on US listings, (b) `AcknowledgmentsCard` needs the attribution footer added, (c) Apple Watch screenshots in the listing need to use Apple's official bezels.

### EU Digital Markets Act (DMA) — sourced from <https://developer.apple.com/support/dma-and-apps-in-the-eu/>

If Rung distributes in the 27 EU member states **only via the App Store** (no alternative marketplaces, no Web Distribution, no external payment), **no extra action is required.** Standard App Store terms apply, no Core Technology Fee, no separate notarization step. ✅

If Rung ever opts into alternative distribution / payment in the EU:
- Must accept the **Alternative Terms Addendum for Apps in the EU**.
- Must submit binaries for **Notarization** (single binary works for both App Store + alternative channels).
- Pays €0.50 per "first annual install" per EU user **only above the 1-million-installs threshold**, with a 3-year free on-ramp for developers under €10M global revenue.
- Provides install-sheet metadata (name, developer, description, screenshots, age rating).

For v1 launch: ignore. Add to a follow-up only if the EU-specific monetization opportunity ever justifies it.

### 5.3 Gaming, Gambling, Lotteries
N/A.

### 5.4 VPN Apps
N/A.

### 5.5 Mobile Device Management
N/A.

---

## Required Info.plist usage descriptions (audit & wording)

| Key | Required value (must read like the user, not the developer) |
|---|---|
| `NSHealthShareUsageDescription` | "Rung reads your workouts, steps, mindful minutes, sleep, hydration, and body mass to verify habits you've checked off and to draw your daily energy curve. Your health data never leaves your account." |
| `NSHealthUpdateUsageDescription` | Set even if unused — Apple's reviewer machine verifies the key exists when `HKHealthStore` is linked. Wording: "Rung does not write to Apple Health." |
| `NSCalendarsUsageDescription` | "Rung reads today's calendar so it can suggest a workout window between meetings." |
| `NSUserNotificationsUsageDescription` | (auto via `requestAuthorization`) "Rung sends nudges from your mentor and reminders to keep your streak." |
| `NSFamilyControlsUsageDescription` | (only when capability is restored) "Rung uses Screen Time to verify you stayed under your social-media cap each day." |
| `NSPushNotificationsUsageDescription` | (registered indirectly via APNs) — same wording as above |

> **Reject signal:** generic strings like "Required for app to function" reliably draw a 5.1.1 reject. The strings above name the *user-facing benefit*.

---

## Capability matrix per platform

| Capability | iOS / iPadOS | macOS | watchOS | Notes |
|---|---|---|---|---|
| `com.apple.developer.applesignin` | ✅ | ✅ | ✅ | All slices auth via Apple |
| `com.apple.developer.healthkit` | ✅ | ✅ | ❌ | Watch reads via iPhone snapshot |
| `com.apple.developer.family-controls` | 🛡️ pending Distribution entitlement | ❌ | ❌ | Stripped from current build |
| `com.apple.security.application-groups` | ✅ `group.jashanveer.Rung` | ✅ | ✅ | Shared with widgets / extension |
| Push notifications | ✅ `aps-environment` set | ❌ | inherits via iPhone | |
| Background modes | `remote-notification`, `processing` | inherits | n/a | Verify `Info.plist` lists only what's actually used. |

---

## Pre-submission checklist (in order)

1. ✅ Family Controls capability removed from build → TestFlight will accept upload.
2. ☐ Set Privacy Policy URL + Support URL in App Store Connect (5.1.1(i), 1.5).
3. ☐ Audit `NSHealthShareUsageDescription` etc. wording per the table above (5.1.1(ii)).
4. ☐ Verify Account → Delete Account is reachable on **iOS, iPad, macOS, watchOS** and that it (a) DELETEs all server-side rows, (b) calls Sign in with Apple's REST `/auth/revoke` endpoint, (c) confirms to the user (5.1.1(v)).
5. ☐ Fill out the App Privacy / Privacy Nutrition Label per the table above, including the Anthropic backend data flow (mentor chat content) and HealthKit types (5.1.2).
6. ☐ Ship (or document deferral of) the report/block UI in the mentor chat **before** any human-mentor pool goes live (1.2).
7. ☐ Re-confirm the bundled `.mov` audio + walker artwork rights (5.2.1).
8. ☐ Submit Family Controls (Distribution) request follow-up if not yet granted; plan a binary update to re-add the capability when approved.
9. ☐ Test the full app on all three Apple platforms in Apple Configurator-style "fresh install + restore from iCloud backup" — Apple reviewers do this.
10. ☐ When uploading: include reviewer notes describing (a) the AI mentor's data flow to Anthropic, (b) how to test mentor chat (no test account needed since Apple Sign-In auto-creates), (c) the deferred Family Controls capability, (d) the HealthKit scoring rationale.

---

## Known follow-ups (post-launch)

- **Tier-weighted leaderboard scoring** (auto × 10 / partial × 5 / self × 1) — requires server-side `AccountabilityService` change. Per CLAUDE.md it's the open scope from the verification pass; not a compliance issue but document in `What's New`.
- **Server-side canonical-registry validator** — same source. Compliance-neutral.
- **Human mentor program** — once enabled, 1.2 (UGC), 3.1.3(d) (P2P payment), and 4.7.5 (chatbot age restriction relax) all become active and must be re-audited.
- **Ad-supported tier** (if ever) — would activate ATT (5.1.2(i)) and 4.5.4 push restrictions; full re-review.
- **Subscription tier** (if ever) — activate 3.1.2 + the 5 required disclosures on the upsell screen, and the deletion flow's "Notify users billing continues through Apple" copy from the account-deletion guide.

---

_Last reviewed: 2026-05-05 against the live App Store Review Guidelines (revision dated by Apple on the page) and the linked sub-pages for Account Deletion + User Privacy & Data Use._
