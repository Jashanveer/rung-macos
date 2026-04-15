# Repository Guidelines

## Project Structure & Module Organization

This repository contains a SwiftUI macOS app generated as an Xcode project. App source lives in `habit-tracker-macos/habit-tracker-macos/`, including `habit_tracker_macosApp.swift`, `ContentView.swift`, `Item.swift`, and `Assets.xcassets`. Unit tests live in `habit-tracker-macos/habit-tracker-macosTests/` and use Swift Testing. UI tests live in `habit-tracker-macos/habit-tracker-macosUITests/` and use XCTest/XCUIAutomation. Keep feature code close to the app target unless it becomes shared enough to justify a separate module.

## Build, Test, and Development Commands

Use Xcode for the primary development loop:

```sh
open habit-tracker-macos.xcodeproj
```

From the command line, build and test with Xcode's build system:

```sh
xcodebuild -project habit-tracker-macos.xcodeproj -scheme habit-tracker-macos build
xcodebuild -project habit-tracker-macos.xcodeproj -scheme habit-tracker-macos test
```

The build command compiles the app target. The test command runs the active test targets configured for the scheme. Prefer Xcode's Product > Run for local manual testing of the macOS app.

## Coding Style & Naming Conventions

Use SwiftUI and SwiftData patterns already present in the project. Indent with 4 spaces. Use `PascalCase` for types, `camelCase` for properties and methods, and `private` for implementation details that do not need wider visibility. SwiftUI views should conform to `View` and keep UI in `body`; state should be scoped with `@State private var` when needed. Prefer `let` for constants, avoid force unwraps, and keep imports minimal (`SwiftUI`, `SwiftData`, `Foundation` only where used).

## Testing Guidelines

Add unit tests in `habit_tracker_macosTests.swift` or nearby test files using Swift Testing's `@Test` and `#expect(...)`. Add end-to-end UI checks in the UI test target using `XCUIApplication`. Name tests after observable behavior, for example `@Test func addingHabitStoresTimestamp()`. Cover persistence and view-model logic with unit tests, and reserve UI tests for user workflows such as launch, add, edit, and delete.

## Commit & Pull Request Guidelines

The current history contains only `Initial Commit`, so keep future commits short, imperative, and focused, for example `Add habit creation form` or `Fix item deletion crash`. Pull requests should include a concise description, testing performed, screenshots for UI changes, and links to any related issue or task. Note any data model or SwiftData migration impact explicitly.

## Agent-Specific Instructions

Keep changes limited to the requested task. Use Xcode project tooling for builds and diagnostics when available, and do not rewrite generated project files unless the change requires it.
