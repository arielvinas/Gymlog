//
//  ExerciseSet.swift
//  Maraton
//
//  Una serie individual de un ejercicio (peso y repeticiones).
//

import Foundation
import SwiftData

@Model
final class ExerciseSet {
    /// Número de serie dentro del ejercicio (1, 2, 3...).
    var order: Int = 0

    /// Peso utilizado en kilogramos.
    var weight: Double?

    /// Repeticiones realizadas.
    var reps: Int?

    /// Indica si la serie fue completada.
    var isDone: Bool = false

    /// Ejercicio al que pertenece.
    var exercise: Exercise?

    init(
        order: Int,
        weight: Double? = nil,
        reps: Int? = nil,
        isDone: Bool = false,
        exercise: Exercise? = nil
    ) {
        self.order = order
        self.weight = weight
        self.reps = reps
        self.isDone = isDone
        self.exercise = exercise
    }

    /// Resumen corto de la serie (ej. "40kg × 10").
    var summary: String {
        let pesoStr = weight.map { "\($0.formattedKg)kg" } ?? "—"
        let repsStr = reps.map { "\($0)" } ?? "—"
        return "\(pesoStr) × \(repsStr)"
    }
}
