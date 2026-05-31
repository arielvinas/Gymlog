//
//  PreviewData.swift
//  Maraton
//
//  Contenedor en memoria con el plan cargado, para los previews de SwiftUI.
//

import Foundation
import SwiftData

enum PreviewData {
    /// ModelContainer en memoria con el plan completo pre-cargado.
    @MainActor static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: WorkoutDay.self, Exercise.self, ExerciseSet.self, DailyCheckIn.self,
            configurations: config
        )
        WorkoutSeed.seedIfNeeded(context: container.mainContext)
        return container
    }()
}
