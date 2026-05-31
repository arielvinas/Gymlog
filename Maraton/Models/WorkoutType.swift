//
//  WorkoutType.swift
//  Maraton
//
//  Tipo de entrenamiento con color y metadatos para la UI.
//

import SwiftUI

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case descanso
    case fuerza
    case rodaje
    case calidad
    case fondo
    case carrera

    var id: String { rawValue }

    /// Nombre legible para mostrar en la interfaz (es-AR).
    var displayName: String {
        switch self {
        case .descanso: return "Descanso"
        case .fuerza:   return "Fuerza"
        case .rodaje:   return "Rodaje"
        case .calidad:  return "Calidad"
        case .fondo:    return "Fondo"
        case .carrera:  return "Carrera"
        }
    }

    /// Color asociado al tipo, usado para el punto en la lista y los acentos.
    var color: Color {
        switch self {
        case .descanso: return .gray
        case .fuerza:   return .purple
        case .rodaje:   return .blue
        case .calidad:  return .orange
        case .fondo:    return .green
        case .carrera:  return .red
        }
    }

    /// Ícono SF Symbol representativo del tipo.
    var symbolName: String {
        switch self {
        case .descanso: return "bed.double.fill"
        case .fuerza:   return "dumbbell.fill"
        case .rodaje:   return "figure.run"
        case .calidad:  return "bolt.fill"
        case .fondo:    return "mountain.2.fill"
        case .carrera:  return "flag.checkered"
        }
    }

    /// Indica si el tipo corresponde a una corrida, donde aplican los
    /// campos de registro (km, duración, esfuerzo).
    var isRun: Bool {
        switch self {
        case .rodaje, .calidad, .fondo, .carrera: return true
        case .descanso, .fuerza:                  return false
        }
    }
}
