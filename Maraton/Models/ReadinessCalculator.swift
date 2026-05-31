//
//  ReadinessCalculator.swift
//  Maraton
//
//  Estimación simple del estado de preparación para la carrera.
//

import SwiftUI

/// Umbrales de adherencia para el semáforo. Ajustables sin tocar la lógica.
struct ReadinessThresholds {
    /// Adherencia mínima para estado verde (0..1).
    var green: Double
    /// Adherencia mínima para estado amarillo (0..1).
    var yellow: Double

    static let `default` = ReadinessThresholds(green: 0.80, yellow: 0.50)
}

/// Estado general de preparación.
enum ReadinessStatus {
    case enRitmo    // 🟢
    case atencion   // 🟡
    case retrasado  // 🔴

    init(adherence: Double, thresholds: ReadinessThresholds) {
        if adherence >= thresholds.green {
            self = .enRitmo
        } else if adherence >= thresholds.yellow {
            self = .atencion
        } else {
            self = .retrasado
        }
    }

    var emoji: String {
        switch self {
        case .enRitmo:   return "🟢"
        case .atencion:  return "🟡"
        case .retrasado: return "🔴"
        }
    }

    var label: String {
        switch self {
        case .enRitmo:   return "En ritmo"
        case .atencion:  return "Atención"
        case .retrasado: return "Retrasado"
        }
    }

    var color: Color {
        switch self {
        case .enRitmo:   return .green
        case .atencion:  return .yellow
        case .retrasado: return .red
        }
    }
}

/// Resultado del cálculo de preparación.
struct Readiness {
    let adherence: Double        // 0..1 (sobre lo que ya debería estar hecho)
    let completedCount: Int
    let dueCount: Int
    let longestFondoKm: Double?
    let activeWeeks: Int
    let status: ReadinessStatus
}

enum ReadinessCalculator {
    /// Calcula la preparación tomando como referencia los días ya vencidos
    /// (fecha <= hoy), para que el semáforo sea significativo desde el inicio.
    static func compute(
        days: [WorkoutDay],
        today: Date = Date(),
        thresholds: ReadinessThresholds = .default
    ) -> Readiness {
        let cal = PlanConstants.calendar
        let todayStart = cal.startOfDay(for: today)

        let dueDays = days.filter { cal.startOfDay(for: $0.date) <= todayStart }
        let completedDue = dueDays.filter { $0.isCompleted }
        let adherence = dueDays.isEmpty ? 1.0 : Double(completedDue.count) / Double(dueDays.count)

        let longestFondo = days
            .filter { $0.type == .fondo && $0.isCompleted }
            .compactMap { $0.actualKm }
            .max()

        let activeWeeks = Set(days.filter { $0.isCompleted }.map { $0.weekTitle }).count

        return Readiness(
            adherence: adherence,
            completedCount: completedDue.count,
            dueCount: dueDays.count,
            longestFondoKm: longestFondo,
            activeWeeks: activeWeeks,
            status: ReadinessStatus(adherence: adherence, thresholds: thresholds)
        )
    }
}
