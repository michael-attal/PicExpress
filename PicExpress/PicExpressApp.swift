//
//  PicExpressApp.swift
//  PicExpress
//
//  Created by Michaël ATTAL on 10/01/2025.
//

import SwiftData
import SwiftUI

@main
struct PicExpressApp: App {
    @State var appState = AppState()

    /// ModelContainer configuration for SwiftData
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PicExpressDocument.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .modelContainer(sharedModelContainer)
                .environment(appState)
        }
    }
}
