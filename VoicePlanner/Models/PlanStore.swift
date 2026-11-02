//
//  PlanStore.swift
//  VoicePlanner
//
//  One ModelContainer shared by the SwiftUI app and the App Intents.
//
//  App Intents declared in the main app target run inside the app's own process
//  (launched in the background when Siri invokes them), so a single static
//  container is enough. No App Group is needed unless you later move the intents
//  into a separate App Intents *extension*; in that case pass an App Group
//  identifier to `groupContainer:`.
//

import SwiftData

@MainActor
enum PlanStore {
    static let shared: ModelContainer = {
        let schema = Schema([Plan.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            // Strictly local. With `.automatic`, SwiftData would start syncing to
            // iCloud as soon as someone adds the CloudKit capability.
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }()
}
