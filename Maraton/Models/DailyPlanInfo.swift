//
//  DailyPlanInfo.swift
//  Maraton
//
//  Información del entrenamiento de hoy para la tarjeta "¿Qué hago hoy?".
//

import SwiftUI

/// Estado del entrenamiento del día.
enum DailyStatus {
    case pending
    case completed
    case rest

    var label: String {
        switch self {
        case .pending:   return "Pendiente"
        case .completed: return "Completado"
        case .rest:      return "Descanso"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return .orange
        case .completed: return .green
        case .rest:      return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .pending:   return "circle.dashed"
        case .completed: return "checkmark.circle.fill"
        case .rest:      return "moon.zzz.fill"
        }
    }
}

extension WorkoutDay {
    /// Titular para la tarjeta de hoy (ej. "Hoy toca Fondo").
    var todayHeadline: String {
        type == .descanso ? "Hoy es día de descanso" : "Hoy toca \(type.displayName)"
    }

    /// Objetivo del día, legible y breve.
    var objective: String {
        switch type {
        case .descanso: return "Descansá y recuperá"
        case .fuerza:   return "Completar sesión de gimnasio"
        default:        return detail.isEmpty ? title : "\(title) · \(detail)"
        }
    }

    /// Estado del día según su tipo y si fue completado.
    var dailyStatus: DailyStatus {
        if type == .descanso { return .rest }
        return isCompleted ? .completed : .pending
    }
}

/// Localiza el entrenamiento correspondiente a una fecha dada.
enum DailyPlanInfo {
    static func workout(in days: [WorkoutDay], on date: Date = Date()) -> WorkoutDay? {
        let cal = PlanConstants.calendar
        return days.first { cal.isDate($0.date, inSameDayAs: date) }
    }
}
