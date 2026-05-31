//
//  MaratonApp.swift
//  Maraton
//
//  Created by Ariel Viñas on 30/05/2026.
//

import SwiftUI
import SwiftData

@main
struct MaratonApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutDay.self, Exercise.self, ExerciseSet.self, DailyCheckIn.self)
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
        // Pre-carga el plan en el primer arranque y aplica las novedades del
        // plan (una vez por versión), respetando los días editados o borrados.
        WorkoutSeed.seedIfNeeded(context: container.mainContext)
        WorkoutSeed.applyPlanUpdates(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
