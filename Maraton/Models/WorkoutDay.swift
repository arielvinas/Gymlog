//
//  WorkoutDay.swift
//  Maraton
//
//  Modelo SwiftData que representa un día del plan de entrenamiento.
//

import Foundation
import SwiftData

@Model
final class WorkoutDay {
    /// Fecha del entrenamiento (única dentro del plan).
    @Attribute(.unique) var date: Date

    /// Título corto (ej. "Fondo largo 12 km").
    var title: String

    /// Detalle breve que acompaña al título (ej. "Z2 conversacional").
    var detail: String

    /// Descripción larga con la explicación del entrenamiento.
    var longDescription: String

    /// Tipo de entrenamiento.
    var type: WorkoutType

    /// Título de la semana a la que pertenece (ej. "Semana 1", "Arranque").
    var weekTitle: String

    /// Etiqueta opcional de la semana (ej. "Pico de volumen", "Taper").
    var weekTag: String?

    /// Orden de la semana para ordenar las secciones de la lista.
    var weekOrder: Int

    /// Indica si el día fue completado.
    var isCompleted: Bool

    /// Ejercicios de gimnasio (solo se usan en días de fuerza).
    @Relationship(deleteRule: .cascade, inverse: \Exercise.day)
    var exercises: [Exercise] = []

    // MARK: - Campos de registro (se completan al marcar como hecho)

    var actualKm: Double?
    var durationMinutes: Int?
    var perceivedEffort: Int?   // 1-10
    var notes: String?

    /// Frecuencia cardíaca promedio (bpm), importada de Apple Salud.
    var avgHeartRate: Double?

    /// Calorías activas quemadas (kcal), importadas de Apple Salud.
    var activeCalories: Double?

    init(
        date: Date,
        title: String,
        detail: String,
        longDescription: String,
        type: WorkoutType,
        weekTitle: String,
        weekTag: String? = nil,
        weekOrder: Int,
        isCompleted: Bool = false,
        actualKm: Double? = nil,
        durationMinutes: Int? = nil,
        perceivedEffort: Int? = nil,
        notes: String? = nil,
        avgHeartRate: Double? = nil,
        activeCalories: Double? = nil
    ) {
        self.date = date
        self.title = title
        self.detail = detail
        self.longDescription = longDescription
        self.type = type
        self.weekTitle = weekTitle
        self.weekTag = weekTag
        self.weekOrder = weekOrder
        self.isCompleted = isCompleted
        self.actualKm = actualKm
        self.durationMinutes = durationMinutes
        self.perceivedEffort = perceivedEffort
        self.notes = notes
        self.avgHeartRate = avgHeartRate
        self.activeCalories = activeCalories
    }

    /// Ritmo promedio en segundos por kilómetro, si hay km y duración.
    var paceSecondsPerKm: Double? {
        guard let km = actualKm, km > 0, let minutes = durationMinutes else { return nil }
        return (Double(minutes) * 60.0) / km
    }

    /// Ejercicios ordenados por su posición en la sesión.
    var orderedExercises: [Exercise] {
        exercises.sorted { $0.order < $1.order }
    }
}
