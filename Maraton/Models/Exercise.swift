//
//  Exercise.swift
//  Maraton
//
//  Ejercicio de un día de gimnasio, con sus series.
//

import Foundation
import SwiftData

@Model
final class Exercise {
    /// Nombre del ejercicio (ej. "Press banca").
    var name: String = ""

    /// Orden dentro de la sesión del día.
    var order: Int = 0

    /// Fecha del día al que pertenece (copiada de `day.date` para
    /// facilitar la búsqueda del histórico "última vez").
    var dayDate: Date = Date()

    /// Notas opcionales del ejercicio.
    var notes: String?

    /// Día de entrenamiento al que pertenece.
    var day: WorkoutDay?

    /// Series del ejercicio.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise)
    var sets: [ExerciseSet] = []

    init(
        name: String,
        order: Int,
        dayDate: Date,
        notes: String? = nil,
        day: WorkoutDay? = nil
    ) {
        self.name = name
        self.order = order
        self.dayDate = dayDate
        self.notes = notes
        self.day = day
    }

    /// Series ordenadas por su número.
    var orderedSets: [ExerciseSet] {
        sets.sorted { $0.order < $1.order }
    }

    /// Indica si tiene al menos una serie con datos registrados.
    var hasLoggedData: Bool {
        sets.contains { $0.reps != nil || $0.weight != nil }
    }
}
