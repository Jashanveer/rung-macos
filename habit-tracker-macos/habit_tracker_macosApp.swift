//
//  habit_tracker_macosApp.swift
//  habit-tracker-macos
//
//  Created by Jashanveer Singh on 4/14/26.
//

import SwiftUI
import SwiftData

@main
struct habit_tracker_macosApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
    }
}
