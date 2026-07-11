//
//  SupplementKind.swift
//  Maraton
//
//  Suplementos soportados y sus metadatos para la UI y recordatorios.
//

import SwiftUI

enum SupplementKind: String, Codable, CaseIterable, Identifiable {
    case creatina
    case proteina

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .creatina: return "Creatina"
        case .proteina: return "Proteína"
        }
    }

    var color: Color {
        switch self {
        case .creatina: return .teal
        case .proteina: return .indigo
        }
    }

    var symbolName: String {
        switch self {
        case .creatina: return "pills.fill"
        case .proteina: return "cup.and.saucer.fill"
        }
    }

    /// Hora por defecto del recordatorio.
    var defaultReminderHour: Int {
        switch self {
        case .creatina: return 9
        case .proteina: return 20
        }
    }

    var notificationTitle: String {
        switch self {
        case .creatina: return "💊 Creatina"
        case .proteina: return "🥤 Proteína"
        }
    }

    var notificationBody: String {
        switch self {
        case .creatina: return "¿Tomaste tu creatina hoy? La constancia es la que rinde."
        case .proteina: return "Acordate de tu proteína. Sumar hábitos suma en el entrenamiento."
        }
    }
}
