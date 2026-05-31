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
}
