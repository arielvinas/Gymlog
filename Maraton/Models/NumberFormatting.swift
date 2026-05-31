//
//  NumberFormatting.swift
//  Maraton
//
//  Helpers de formato numérico en español (es-AR).
//

import Foundation

extension Double {
    /// Formatea kilómetros con hasta un decimal y coma decimal (ej. "12,5").
    var formattedKm: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_AR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    /// Formatea kilogramos con hasta un decimal y coma decimal (ej. "42,5").
    var formattedKg: String {
        formattedKm
    }

    /// Interpreta el valor como segundos por km y lo formatea como ritmo
    /// (ej. 330 → "5'30\"/km").
    var formattedPace: String {
        let totalSeconds = Int(rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d'%02d\"/km", minutes, seconds)
    }
}
