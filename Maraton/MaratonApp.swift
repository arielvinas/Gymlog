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
        // Pre-carga el plan en el primer arranque y agrega los días nuevos
        // del plan que falten en instalaciones existentes.
        WorkoutSeed.seedIfNeeded(context: container.mainContext)
        WorkoutSeed.syncPlan(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
