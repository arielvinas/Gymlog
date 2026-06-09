//
//  StrengthProgress.swift
//  Maraton
//
//  Métricas simples de evolución de fuerza a partir de Exercise/ExerciseSet.
//  No modifica la estructura de datos existente.
//

import Foundation

/// Resumen de la mejor serie de una sesión (la de mayor peso).
struct TopSet {
    let weight: Double
    let reps: Int

    var text: String {
        "\(weight.formattedKg) kg × \(reps)"
    }
}

/// Comparación de un ejercicio entre su última sesión y la anterior.
struct ExerciseImprovement: Identifiable {
    let id = UUID()
    let name: String
    let lastDate: Date
    let last: TopSet
    let previous: TopSet
    /// Variación porcentual del peso de la mejor serie.
    let percentChange: Double
}

enum StrengthProgress {
    /// Mejores series recientes comparadas con la sesión previa del mismo
    /// ejercicio, ordenadas por fecha (más recientes primero).
    static func recentImprovements(exercises: [Exercise], limit: Int = 5) -> [ExerciseImprovement] {
        let porNombre = Dictionary(grouping: exercises, by: { $0.name })

        var resultado: [ExerciseImprovement] = []
        for (nombre, sesiones) in porNombre {
            // Sesiones con datos, ordenadas de más nueva a más vieja.
            let conDatos = sesiones
                .compactMap { ejercicio -> (date: Date, top: TopSet)? in
                    guard let top = topSet(of: ejercicio) else { return nil }
                    return (ejercicio.dayDate, top)
                }
                .sorted { $0.date > $1.date }

            guard conDatos.count >= 2 else { continue }
            let ultima = conDatos[0]
            let anterior = conDatos[1]
            guard anterior.top.weight > 0 else { continue }

            let cambio = (ultima.top.weight - anterior.top.weight) / anterior.top.weight * 100
            resultado.append(
                ExerciseImprovement(
                    name: nombre,
                    lastDate: ultima.date,
                    last: ultima.top,
                    previous: anterior.top,
                    percentChange: cambio
                )
            )
        }

        return resultado
            .sorted { $0.lastDate > $1.lastDate }
            .prefix(limit)
            .map { $0 }
    }

    /// La mejor serie del ejercicio: mayor peso (desempata por reps).
    private static func topSet(of exercise: Exercise) -> TopSet? {
        let conPeso = exercise.orderedSets.compactMap { set -> (Double, Int)? in
            guard let w = set.weight else { return nil }
            return (w, set.reps ?? 0)
        }
        guard let best = conPeso.max(by: { ($0.0, $0.1) < ($1.0, $1.1) }) else { return nil }
        return TopSet(weight: best.0, reps: best.1)
    }
}
