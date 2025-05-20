//
//  InchForwardApp.swift
//  InchForward
//
//  Created by Darrion Johnson on 5/20/25.
//

import SwiftUI
import SwiftData

@main
struct InchForwardApp: App {
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([Goal.self, Move.self, DailyProgress.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false) // Set to true for testing
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView(modelContext: container.mainContext)
        }
        .modelContainer(container) // Makes it available in the environment
    }
}
