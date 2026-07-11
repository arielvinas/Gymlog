//
//  TestSupport.swift
//  GymLogTests
//
//  Utilidades compartidas por los tests. Ver TESTING.md para el backlog.
//

import Foundation
import SwiftData
import Testing
@testable import Maraton

// MARK: - Base de datos en memoria

/// Base de datos efímera y aislada para un test: sin disco y sin CloudKit.
///
/// **Guardala en una variable del test.** El `ModelContext` no mantiene vivo a su
/// `ModelContainer`: si el contenedor se libera, el contexto queda colgado y el
/// test **crashea con SIGTRAP** (no falla: crashea, y se lleva puesto al resto de
/// los tests del proceso). Este tipo existe para que los dos vivan juntos.
///
/// ```swift
/// let db = TestDB()
/// makeDay(date(2026, 7, 1), in: db.context)
/// ```
@MainActor
struct TestDB {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() {
        container = AppData.makeContainer(inMemory: true)
    }
}

// MARK: - Fechas

/// Fecha determinística, a mediodía.
///
/// **Usar siempre esto en vez de construir fechas a mano.** `PlanConstants.calendar`
/// y los `DateFormatter` de la app usan la timezone del dispositivo; una fecha a
/// medianoche puede caer en el día anterior o siguiente según dónde corra el test.
/// Mediodía deja margen en ambas direcciones.
func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    DateComponents.makeDate(year: year, month: month, day: day)
}

// MARK: - Constructores de modelos

/// Un día del plan, con lo mínimo indispensable.
@MainActor
@discardableResult
func makeDay(
    _ date: Date,
    type: WorkoutType = .fuerza,
    title: String = "Fuerza A",
    detail: String = "",
    weekTitle: String = "Semana 1",
    weekTag: String? = nil,
    weekOrder: Int = 1,
    isCompleted: Bool = false,
    actualKm: Double? = nil,
    durationMinutes: Int? = nil,
    in context: ModelContext? = nil
) -> WorkoutDay {
    let day = WorkoutDay(
        date: date,
        title: title,
        detail: detail,
        longDescription: "",
        type: type,
        weekTitle: weekTitle,
        weekTag: weekTag,
        weekOrder: weekOrder,
        isCompleted: isCompleted,
        actualKm: actualKm,
        durationMinutes: durationMinutes
    )
    context?.insert(day)
    return day
}

/// Un ejercicio con sus series. `sets` es la lista de `(peso, reps)` — usar `nil`
/// para dejar el campo vacío, que es como quedan las series recién sembradas.
@MainActor
@discardableResult
func makeExercise(
    _ name: String = "Press banca",
    on day: WorkoutDay,
    order: Int = 0,
    targetReps: String? = nil,
    restSeconds: Int? = nil,
    sets: [(weight: Double?, reps: Int?)] = [],
    in context: ModelContext? = nil
) -> Exercise {
    let exercise = Exercise(
        name: name,
        order: order,
        dayDate: day.date,
        targetReps: targetReps,
        restSeconds: restSeconds,
        day: day
    )
    context?.insert(exercise)

    exercise.sets = sets.enumerated().map { index, spec in
        let set = ExerciseSet(order: index + 1, weight: spec.weight, reps: spec.reps)
        set.exercise = exercise
        context?.insert(set)
        return set
    }
    return exercise
}
