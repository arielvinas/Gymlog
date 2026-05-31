//
//  RaceProjection.swift
//  Maraton
//
//  Proyección simple de tiempos de carrera a partir del ritmo promedio.
//  La estrategia es reemplazable por algoritmos más sofisticados.
//

import Foundation

/// Una corrida completada, reducida a lo necesario para proyectar.
struct RunSample {
    let date: Date
    let km: Double
    let durationSeconds: Double

    var paceSecPerKm: Double? {
        km > 0 ? durationSeconds / km : nil
    }
}

/// Resultado de la proyección.
struct RaceProjection {
    let pace30dSecPerKm: Double?
    let paceRecentSecPerKm: Double?
    let basePaceSecPerKm: Double
    let time10kSeconds: Double
    let timeHalfSeconds: Double
}

/// Estrategia de proyección. Implementar para cambiar el modelo de cálculo.
protocol RaceProjectionStrategy {
    func project(from runs: [RunSample], today: Date) -> RaceProjection?
}

/// Estrategia por defecto: ritmo promedio ponderado por distancia, con un
/// pequeño factor de fatiga para la media maratón.
struct AveragePaceProjection: RaceProjectionStrategy {
    /// Factor de desgaste aplicado al ritmo en la media (1.0 = sin desgaste).
    var halfFadeFactor: Double = 1.03
    /// Ventana en días para el ritmo reciente.
    var recentDays: Int = 30
    /// Distancia mínima acumulada para el ritmo "de fondo" (km).
    var minRecentKm: Double = 10

    func project(from runs: [RunSample], today: Date) -> RaceProjection? {
        let cal = PlanConstants.calendar

        // Ritmo de los últimos N días (distancia/tiempo totales).
        let windowStart = cal.date(byAdding: .day, value: -recentDays, to: today) ?? today
        let pace30d = weightedPace(of: runs.filter { $0.date >= windowStart })

        // Ritmo de las corridas más recientes hasta sumar >= minRecentKm.
        let recent = runsUntilDistance(runs, minKm: minRecentKm)
        let paceRecent = weightedPace(of: recent)

        guard let base = paceRecent ?? pace30d else { return nil }

        return RaceProjection(
            pace30dSecPerKm: pace30d,
            paceRecentSecPerKm: paceRecent,
            basePaceSecPerKm: base,
            time10kSeconds: base * 10,
            timeHalfSeconds: base * PlanConstants.raceDistanceKm * halfFadeFactor
        )
    }

    /// Ritmo ponderado: suma de duraciones / suma de distancias.
    private func weightedPace(of runs: [RunSample]) -> Double? {
        let totalKm = runs.reduce(0) { $0 + $1.km }
        let totalSeconds = runs.reduce(0) { $0 + $1.durationSeconds }
        return totalKm > 0 ? totalSeconds / totalKm : nil
    }

    /// Toma las corridas más recientes hasta acumular `minKm`.
    private func runsUntilDistance(_ runs: [RunSample], minKm: Double) -> [RunSample] {
        let ordered = runs.sorted { $0.date > $1.date }
        var acumulado = 0.0
        var resultado: [RunSample] = []
        for run in ordered {
            resultado.append(run)
            acumulado += run.km
            if acumulado >= minKm { break }
        }
        return acumulado >= minKm ? resultado : []
    }
}

enum RaceProjectionBuilder {
    /// Construye las muestras de corrida válidas a partir del plan.
    static func samples(from days: [WorkoutDay]) -> [RunSample] {
        days.compactMap { day in
            guard day.isCompleted, day.type.isRun,
                  let km = day.actualKm, km > 0,
                  let minutes = day.durationMinutes, minutes > 0 else { return nil }
            return RunSample(date: day.date, km: km, durationSeconds: Double(minutes) * 60)
        }
    }
}
