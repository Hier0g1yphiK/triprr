//
//  triprrApp.swift
//  triprr
//
//  Created by John McCullough on 03/10/2026.
//

import SwiftUI
import SwiftData

@main
struct triprrApp: App {
    var sharedModelContainer: ModelContainer = {
        let modelConfiguration = ModelConfiguration(
            schema: currentSchema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: currentSchema,
                migrationPlan: TriprrMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appServices, .live)
        }
        .modelContainer(sharedModelContainer)
    }
}
